import Foundation
import TensorFlowLiteC

/// iOS implementation of EmbeddingGemma model - equivalent to Android LiteRT implementation
/// Supports any .tflite embedding model with 768-dimensional output
class EmbeddingModel {

    // MARK: - Properties
    // TfLiteInterpreter* — owned, deleted in close()
    private var interpreter: OpaquePointer?
    private var tokenizer: TokenizerProtocol?
    private let modelPath: String
    private let tokenizerPath: String

    // Model configuration — detected from model tensors after allocateTensors
    private var maxSequenceLength = 1024
    private var embeddingDimension = 768

    private let taskPrefix = "task: search result | query: "
    private let docPrefix = "title: none | text: "

    // Memory optimization: reuse buffers to avoid per-inference allocations
    private var paddedTokensBuffer: [Int32] = []
    private var outputBuffer: [Float] = []

    // MARK: - Initialization

    init(modelPath: String, tokenizerPath: String, useGPU: Bool = true) {
        self.modelPath = modelPath
        self.tokenizerPath = tokenizerPath
        // useGPU kept for API compatibility; threading handles performance
    }

    /// Load model and tokenizer (equivalent to Android's loadModel)
    func loadModel() throws {
        tokenizer = try EmbeddingModel.loadTokenizer(jsonPath: tokenizerPath)

        // Load model from file
        guard let model = TfLiteModelCreateFromFile(modelPath) else {
            throw EmbeddingError.modelLoadFailed("TfLiteModelCreateFromFile failed for: \(modelPath)")
        }
        defer { TfLiteModelDelete(model) }

        // Build interpreter options
        guard let options = TfLiteInterpreterOptionsCreate() else {
            throw EmbeddingError.modelLoadFailed("Failed to create interpreter options")
        }
        defer { TfLiteInterpreterOptionsDelete(options) }

        TfLiteInterpreterOptionsSetNumThreads(options, 6)

        // XNNPACK required for correct mixed-precision inference.
        // Was disabled in v0.11.16 (#155) due to SentencePiece C++ protobuf conflict —
        // now resolved (pure Swift BPETokenizer).
        var xnnpackOptions = TfLiteXNNPackDelegateOptionsDefault()
        xnnpackOptions.num_threads = 6
        if let xnnpackDelegate = TfLiteXNNPackDelegateCreate(&xnnpackOptions) {
            TfLiteInterpreterOptionsAddDelegate(options, xnnpackDelegate)
            // Delegate is owned by the interpreter after this point
        }

        guard let interp = TfLiteInterpreterCreate(model, options) else {
            throw EmbeddingError.modelLoadFailed("TfLiteInterpreterCreate failed")
        }

        guard TfLiteInterpreterAllocateTensors(interp) == kTfLiteOk else {
            TfLiteInterpreterDelete(interp)
            throw EmbeddingError.modelLoadFailed("TfLiteInterpreterAllocateTensors failed")
        }

        // Detect sequence length from input tensor shape [1, seqLen]
        if let inputTensor = TfLiteInterpreterGetInputTensor(interp, 0) {
            let dims = TfLiteTensorNumDims(inputTensor)
            if dims >= 2 {
                let detected = Int(TfLiteTensorDim(inputTensor, 1))
                if detected > 0 { maxSequenceLength = detected }
            }
        }

        // Detect embedding dimension from output tensor shape [1, dim]
        if let outputTensor = TfLiteInterpreterGetOutputTensor(interp, 0) {
            let dims = TfLiteTensorNumDims(outputTensor)
            if dims >= 2 {
                let detected = Int(TfLiteTensorDim(outputTensor, 1))
                if detected > 0 { embeddingDimension = detected }
            }
        }

        interpreter = interp
    }

    /// Generate embeddings for input text (equivalent to Android's generateEmbedding)
    func generateEmbedding(for text: String) throws -> [Float] {
        return try runInference(fullText: taskPrefix + text)
    }

    /// Generate embeddings using document prefix (for RAG indexing)
    func generateDocumentEmbedding(for text: String) throws -> [Float] {
        return try runInference(fullText: docPrefix + text)
    }

    /// Close model and release resources
    func close() {
        if let interp = interpreter {
            TfLiteInterpreterDelete(interp)
            interpreter = nil
        }
        tokenizer = nil
        paddedTokensBuffer.removeAll()
        outputBuffer.removeAll()
    }

    // MARK: - Private Methods

    private func runInference(fullText: String) throws -> [Float] {
        guard let interp = interpreter, let tokenizer = tokenizer else {
            throw EmbeddingError.modelNotLoaded("Model not loaded. Call loadModel() first.")
        }

        var tokens = tokenizer.encode(fullText)
        tokens.insert(2, at: 0)  // BOS (Gemma vocabulary)
        tokens.append(1)         // EOS

        // Pad/truncate to maxSequenceLength into Int32 buffer
        let seqLen = maxSequenceLength
        if paddedTokensBuffer.count != seqLen {
            paddedTokensBuffer = [Int32](repeating: 0, count: seqLen)
        }
        let copyCount = min(tokens.count, seqLen)
        for i in 0..<copyCount { paddedTokensBuffer[i] = Int32(tokens[i]) }
        for i in copyCount..<seqLen { paddedTokensBuffer[i] = 0 }

        // Copy into input tensor
        guard let inputTensor = TfLiteInterpreterGetInputTensor(interp, 0) else {
            throw EmbeddingError.inferenceFailed("Cannot get input tensor")
        }
        let byteCount = seqLen * MemoryLayout<Int32>.size
        let status = paddedTokensBuffer.withUnsafeBytes { ptr in
            TfLiteTensorCopyFromBuffer(inputTensor, ptr.baseAddress!, byteCount)
        }
        guard status == kTfLiteOk else {
            throw EmbeddingError.inferenceFailed("TfLiteTensorCopyFromBuffer failed")
        }

        // Run inference
        guard TfLiteInterpreterInvoke(interp) == kTfLiteOk else {
            throw EmbeddingError.inferenceFailed("TfLiteInterpreterInvoke failed")
        }

        // Extract output
        guard let outputTensor = TfLiteInterpreterGetOutputTensor(interp, 0) else {
            throw EmbeddingError.inferenceFailed("Cannot get output tensor")
        }
        let outputByteCount = TfLiteTensorByteSize(outputTensor)
        let floatCount = outputByteCount / MemoryLayout<Float>.size
        if outputBuffer.count != floatCount {
            outputBuffer = [Float](repeating: 0.0, count: floatCount)
        }
        outputBuffer.withUnsafeMutableBytes { ptr in
            TfLiteTensorCopyToBuffer(outputTensor, ptr.baseAddress!, outputByteCount)
        }

        guard outputBuffer.count >= embeddingDimension else {
            throw EmbeddingError.invalidOutput("Unexpected embedding dimension: \(outputBuffer.count)")
        }
        return Array(outputBuffer.prefix(embeddingDimension))
    }

    private static func loadTokenizer(jsonPath: String) throws -> TokenizerProtocol {
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              let type = model["type"] as? String else {
            throw NSError(domain: "EmbeddingModel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot detect tokenizer type from JSON"])
        }
        switch type {
        case "BPE":    return try BPETokenizer(jsonPath: jsonPath)
        case "Unigram": return try UnigramTokenizer(jsonPath: jsonPath)
        default:
            throw NSError(domain: "EmbeddingModel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown tokenizer type: \(type)"])
        }
    }
}

// MARK: - Error Types

enum EmbeddingError: Error, LocalizedError {
    case modelNotLoaded(String)
    case modelLoadFailed(String)
    case tokenizationFailed(String)
    case invalidOutput(String)
    case inferenceFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded(let message):
            return "Model not loaded: \(message)"
        case .modelLoadFailed(let message):
            return "Model load failed: \(message)"
        case .tokenizationFailed(let message):
            return "Tokenization failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid output: \(message)"
        case .inferenceFailed(let message):
            return "Inference failed: \(message)"
        }
    }
}

// MARK: - Extensions for debugging

extension EmbeddingModel {

    var modelInfo: [String: Any] {
        guard let interp = interpreter else {
            return ["status": "not_loaded"]
        }
        var info: [String: Any] = [
            "status": "loaded",
            "max_sequence_length": maxSequenceLength,
            "embedding_dimension": embeddingDimension,
            "input_tensor_count": TfLiteInterpreterGetInputTensorCount(interp),
            "output_tensor_count": TfLiteInterpreterGetOutputTensorCount(interp),
        ]
        if let t = TfLiteInterpreterGetInputTensor(interp, 0) {
            info["input_dims"] = TfLiteTensorNumDims(t)
        }
        if let t = TfLiteInterpreterGetOutputTensor(interp, 0) {
            info["output_dims"] = TfLiteTensorNumDims(t)
        }
        return info
    }

    func testEmbedding() throws -> [Float] {
        return try generateEmbedding(for: "machine learning algorithms")
    }
}

