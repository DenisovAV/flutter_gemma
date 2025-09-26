import Foundation
import TensorFlowLite

/// iOS implementation of EmbeddingGemma model - equivalent to Android LiteRT implementation
/// Supports any .tflite embedding model with 768-dimensional output
class EmbeddingModel {
    
    // MARK: - Properties
    private var interpreter: Interpreter?
    private var tokenizer: HuggingFaceTokenizer?
    private let modelPath: String
    private let tokenizerPath: String
    private let useGPU: Bool
    
    // Model configuration
    private var maxSequenceLength = 1024 // Will be detected from model
    private var embeddingDimension = 768 // Will be detected from model

    // Optimization: Cache tokenized prefix to avoid repeated tokenization
    private var cachedPrefixTokens: [Int] = []
    private let taskPrefix = "task: search result | query: "

    // Memory optimization: Reuse buffers to avoid allocations
    private var inputBuffer: Data?
    private var paddedTokensBuffer: [Int] = []
    private var outputBuffer: [Float] = []
    
    // MARK: - Initialization
    
    /// Initialize embedding model with paths
    /// - Parameters:
    ///   - modelPath: Path to .tflite model file
    ///   - tokenizerPath: Path to tokenizer.json file
    ///   - useGPU: Whether to use GPU acceleration
    init(modelPath: String, tokenizerPath: String, useGPU: Bool = true) {
        self.modelPath = modelPath
        self.tokenizerPath = tokenizerPath
        self.useGPU = useGPU
    }
    
    /// Load model and tokenizer (equivalent to Android's loadModel)
    func loadModel() throws {
        // Load tokenizer first
        tokenizer = try HuggingFaceTokenizer(tokenizerPath: tokenizerPath)

        // Configure TensorFlow Lite options
        var options = Interpreter.Options()
        options.threadCount = 4 // Optimize for mobile performance
        
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

            // Optimization: Pre-tokenize task prefix once during initialization
            initializePrefixCache()

        } catch {
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

        // Tokenization
        let textTokens = tokenizer.encode(text)

        // Use cached prefix if available, otherwise fallback to full tokenization
        let tokens: [Int]
        if !cachedPrefixTokens.isEmpty {
            tokens = cachedPrefixTokens + textTokens
        } else {
            // Fallback to old method if cache not initialized
            let prompt = taskPrefix + text
            tokens = tokenizer.encode(prompt)
        }

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
    
    /// Close model and release resources
    func close() {
        interpreter = nil
        tokenizer = nil
        cachedPrefixTokens.removeAll()

        // Clear reusable buffers to free memory
        inputBuffer = nil
        paddedTokensBuffer.removeAll()
        outputBuffer.removeAll()
    }
    
    // MARK: - Private Methods

    /// Initialize prefix token cache for performance optimization
    private func initializePrefixCache() {
        guard let tokenizer = tokenizer else {
            return
        }

        // Tokenize the task prefix once and cache it
        cachedPrefixTokens = tokenizer.encode(taskPrefix)
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

        // Fill remaining with padding (0)
        for i in copyCount..<length {
            buffer[i] = 0
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

        // Handle different output tensor shapes
        if outputBuffer.count == embeddingDimension {
            // Direct embedding output - return copy to avoid buffer modification
            return Array(outputBuffer)
        } else if outputBuffer.count > embeddingDimension {
            // Sequence output - take mean pooling or last token
            return meanPooling(embeddings: outputBuffer)
        } else {
            throw EmbeddingError.invalidOutput("Unexpected embedding dimension: \(outputBuffer.count)")
        }
    }
    
    private func meanPooling(embeddings: [Float]) -> [Float] {
        // Apply mean pooling for sequence embeddings
        let sequenceLength = embeddings.count / embeddingDimension
        var pooledEmbeddings = [Float](repeating: 0.0, count: embeddingDimension)

        for i in 0..<embeddingDimension {
            var sum: Float = 0.0
            for j in 0..<sequenceLength {
                sum += embeddings[j * embeddingDimension + i]
            }
            pooledEmbeddings[i] = sum / Float(sequenceLength)
        }

        return pooledEmbeddings
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

// MARK: - High-level wrapper like Android GemmaEmbeddingModel

/// High-level wrapper for EmbeddingModel that mimics Android GemmaEmbeddingModel API
class GemmaEmbeddingWrapper {
    private let embeddingModel: EmbeddingModel
    
    /// Task types for embedding generation
    enum TaskType: String {
        case semanticSimilarity = "search result"
        case clustering = "clustering"
        case classification = "classification"
        case retrieval = "retrieval"
    }
    
    /// Initialize wrapper with model and tokenizer paths
    init(modelPath: String, tokenizerPath: String, useGPU: Bool = false) throws {
        embeddingModel = EmbeddingModel(
            modelPath: modelPath,
            tokenizerPath: tokenizerPath,
            useGPU: useGPU
        )
    }
    
    /// Initialize the underlying model
    func initialize() throws {
        try embeddingModel.loadModel()
    }
    
    /// Generate embedding for text with specified task type (like Android API)
    func embed(text: String, task: TaskType = .semanticSimilarity) throws -> [Double] {
        // Automatically add task prefix like Android version
        let prompt = "task: \(task.rawValue) | query: \(text)"
        let embeddings = try embeddingModel.generateEmbedding(for: prompt)
        
        // Convert Float to Double for consistency with Android API
        return embeddings.map { Double($0) }
    }
    
    /// Close the model and release resources
    func close() {
        embeddingModel.close()
    }
    
    /// Get model information for debugging
    var modelInfo: [String: Any] {
        return embeddingModel.modelInfo
    }
}