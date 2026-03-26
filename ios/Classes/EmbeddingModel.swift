import Foundation
import TensorFlowLite

/// iOS implementation of EmbeddingGemma model - equivalent to Android LiteRT implementation
/// Supports any .tflite embedding model with 768-dimensional output
class EmbeddingModel {
    
    // MARK: - Properties
    private var interpreter: Interpreter?
    private var tokenizer: TokenizerProtocol?
    private let modelPath: String
    private let tokenizerPath: String
    private let useGPU: Bool
    
    // Model configuration
    private var maxSequenceLength = 1024 // Will be detected from model
    private var embeddingDimension = 768 // Will be detected from model

    private let taskPrefix = "task: search result | query: "
    private let docPrefix = "title: none | text: "

    // Memory optimization: Reuse buffers to avoid allocations
    private var inputBuffer: Data?
    private var paddedTokensBuffer: [Int] = []
    private var outputBuffer: [Float] = []

    
    // MARK: - Initialization
    
    /// Initialize embedding model with paths
    /// - Parameters:
    ///   - modelPath: Path to .tflite model file
    ///   - tokenizerPath: Path to sentencepiece.model file
    ///   - useGPU: Whether to use GPU acceleration
    init(modelPath: String, tokenizerPath: String, useGPU: Bool = true) {
        self.modelPath = modelPath
        self.tokenizerPath = tokenizerPath
        self.useGPU = useGPU
    }
    
    /// Load model and tokenizer (equivalent to Android's loadModel)
    func loadModel() throws {
        // Auto-detect tokenizer type from JSON model.type field
        tokenizer = try EmbeddingModel.loadTokenizer(jsonPath: tokenizerPath)

        // Configure TensorFlow Lite options
        var options = Interpreter.Options()
        options.threadCount = 4 // Optimize for mobile performance

        // XNNPACK required for correct mixed-precision inference
        // Was disabled in v0.11.16 (#155) due to crash, but root cause was
        // SentencePiece C++ protobuf conflict — now resolved (pure Swift BPETokenizer)
        options.isXNNPackEnabled = true

        // Note: Select TF Ops should be automatically available when TensorFlowLiteSelectTfOps is linked

        // Load the model with optimized settings
        do {
            // Use optimized threading based on GPU preference
            if useGPU {
                options.threadCount = 6 // Use more threads for GPU-level performance
            } else {
                options.threadCount = 4
            }

            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter?.allocateTensors()

            // Extract dimensions from model tensors
            if let inputTensor = try? interpreter?.input(at: 0) {
                let detectedSequenceLength = inputTensor.shape.dimensions[1]
                if detectedSequenceLength != maxSequenceLength {
                    maxSequenceLength = detectedSequenceLength
                }
            }

            if let outputTensor = try? interpreter?.output(at: 0) {
                let detectedEmbeddingDimension = outputTensor.shape.dimensions[1]
                if detectedEmbeddingDimension != embeddingDimension {
                    embeddingDimension = detectedEmbeddingDimension
                }
            }

        } catch let error as InterpreterError {
            print("[MODEL] InterpreterError: \(error)")
            throw EmbeddingError.modelLoadFailed("InterpreterError: \(error)")
        } catch {
            print("[MODEL] Unknown error: \(error)")
            throw EmbeddingError.modelLoadFailed("Failed to load model: \(error.localizedDescription)")
        }
    }
    
    /// Generate embeddings for input text (equivalent to Android's generateEmbedding)
    /// - Parameter text: Input text to embed
    /// - Returns: 768-dimensional embedding vector
    func generateEmbedding(for text: String) throws -> [Float] {
        guard let interpreter = interpreter,
              let tokenizer = tokenizer else {
            throw EmbeddingError.modelNotLoaded("Model not loaded. Call loadModel() first.")
        }

        // Tokenize full string in one call (not prefix + text separately)
        // This matches Android behavior where SentencePiece encodes the complete string
        let fullText = taskPrefix + text
        var tokens = tokenizer.encode(fullText)

        // Add BOS at beginning and EOS at end - ONCE for entire sequence
        // BOS token ID = 2, EOS token ID = 1 (from Gemma vocabulary)
        tokens.insert(2, at: 0)  // Add BOS
        tokens.append(1)         // Add EOS

        // Prepare and copy input tensor
        let inputTensor = try prepareInputTensor(tokens: tokens)
        try interpreter.copy(inputTensor, toInputAt: 0)

        // Run inference
        try interpreter.invoke()

        // Extract embeddings from output
        let outputTensor = try interpreter.output(at: 0)
        let embeddings = try extractEmbeddings(from: outputTensor)

        return embeddings
    }
    
    /// Generate embeddings for input text using document prefix (for RAG indexing)
    func generateDocumentEmbedding(for text: String) throws -> [Float] {
        guard let interpreter = interpreter,
              let tokenizer = tokenizer else {
            throw EmbeddingError.modelNotLoaded("Model not loaded. Call loadModel() first.")
        }

        let fullText = docPrefix + text
        var tokens = tokenizer.encode(fullText)
        tokens.insert(2, at: 0)  // BOS
        tokens.append(1)         // EOS

        let inputTensor = try prepareInputTensor(tokens: tokens)
        try interpreter.copy(inputTensor, toInputAt: 0)
        try interpreter.invoke()

        let outputTensor = try interpreter.output(at: 0)
        return try extractEmbeddings(from: outputTensor)
    }

    /// Close model and release resources
    func close() {
        interpreter = nil
        tokenizer = nil

        // Clear reusable buffers to free memory
        inputBuffer = nil
        paddedTokensBuffer.removeAll()
        outputBuffer.removeAll()
    }
    
    // MARK: - Private Methods

    /// Load tokenizer by auto-detecting type from tokenizer.json
    private static func loadTokenizer(jsonPath: String) throws -> TokenizerProtocol {
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              let type = model["type"] as? String else {
            throw NSError(domain: "EmbeddingModel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot detect tokenizer type from JSON"])
        }

        switch type {
        case "BPE":
            return try BPETokenizer(jsonPath: jsonPath)
        case "Unigram":
            return try UnigramTokenizer(jsonPath: jsonPath)
        default:
            throw NSError(domain: "EmbeddingModel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown tokenizer type: \(type)"])
        }
    }

    private func prepareInputTensor(tokens: [Int]) throws -> Data {
        // Pad or truncate to maxSequenceLength (reusing buffer)
        padTokens(tokens, toLength: maxSequenceLength, intoBuffer: &paddedTokensBuffer)

        // Reuse input buffer if possible
        let requiredSize = paddedTokensBuffer.count * MemoryLayout<Int32>.size
        if inputBuffer == nil || inputBuffer!.count != requiredSize {
            inputBuffer = Data(count: requiredSize)
        }

        // Copy Int tokens to Int32 buffer efficiently
        inputBuffer!.withUnsafeMutableBytes { bytes in
            let int32Pointer = bytes.bindMemory(to: Int32.self)
            for i in 0..<paddedTokensBuffer.count {
                int32Pointer[i] = Int32(paddedTokensBuffer[i])
            }
        }

        return inputBuffer!
    }
    
    private func padTokens(_ tokens: [Int], toLength length: Int, intoBuffer buffer: inout [Int]) {
        // Resize buffer if needed
        if buffer.count != length {
            buffer = Array(repeating: 0, count: length)
        }

        // Copy tokens and handle truncation/padding
        let copyCount = min(tokens.count, length)

        // Copy input tokens
        for i in 0..<copyCount {
            buffer[i] = tokens[i]
        }

        // Fill remaining with PAD token (0)
        // PAD=0 is standard for Gemma vocabulary
        let padToken = 0
        for i in copyCount..<length {
            buffer[i] = padToken
        }
    }
    
    private func extractEmbeddings(from tensor: Tensor) throws -> [Float] {
        // Extract embeddings from output tensor
        let outputData = tensor.data

        // Convert bytes to Float32 array (reusing buffer)
        let floatCount = outputData.count / MemoryLayout<Float>.size

        // Resize output buffer if needed
        if outputBuffer.count != floatCount {
            outputBuffer = [Float](repeating: 0.0, count: floatCount)
        }

        outputData.withUnsafeBytes { bytes in
            let floatPointer = bytes.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                outputBuffer[i] = floatPointer[i]
            }
        }

        // Model returns [1, 768] - just take the 768 values directly
        // No mean pooling - model already outputs final embedding
        if outputBuffer.count >= embeddingDimension {
            var result = [Float](repeating: 0.0, count: embeddingDimension)
            for i in 0..<embeddingDimension {
                result[i] = outputBuffer[i]
            }

            return result
        } else {
            throw EmbeddingError.invalidOutput("Unexpected embedding dimension: \(outputBuffer.count)")
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
    
    /// Get model information for debugging
    var modelInfo: [String: Any] {
        guard let interpreter = interpreter else {
            return ["status": "not_loaded"]
        }
        
        var info: [String: Any] = [
            "status": "loaded",
            "use_gpu": useGPU,
            "max_sequence_length": maxSequenceLength,
            "embedding_dimension": embeddingDimension,
            "input_tensor_count": interpreter.inputTensorCount,
            "output_tensor_count": interpreter.outputTensorCount
        ]
        
        // Add tensor shapes if available
        if let inputTensor = try? interpreter.input(at: 0) {
            info["input_shape"] = inputTensor.shape.dimensions
            info["input_type"] = "\(inputTensor.dataType)"
        }
        
        if let outputTensor = try? interpreter.output(at: 0) {
            info["output_shape"] = outputTensor.shape.dimensions
            info["output_type"] = "\(outputTensor.dataType)"
        }
        
        return info
    }
    
    /// Test embedding generation with sample text
    func testEmbedding() throws -> [Float] {
        let testText = "machine learning algorithms"
        return try generateEmbedding(for: testText)
    }
}

