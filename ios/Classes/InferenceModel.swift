import Foundation
import MediaPipeTasksGenAI
import MediaPipeTasksGenAIC

struct InferenceModel {
    private(set) var inference: LlmInference

    init(modelPath: String,
         maxTokens: Int,
         supportedLoraRanks: [Int]? = nil,
         maxNumImages: Int = 0) throws {

        let fileManager = FileManager.default
        guard let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "InferenceModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document directory not found"])
        }

        let fileName = (modelPath as NSString).lastPathComponent
        let resolvedPath = documentDirectory.appendingPathComponent(fileName).path
        let llmOptions = LlmInference.Options(modelPath: resolvedPath)

        llmOptions.maxTokens = maxTokens
        llmOptions.waitForWeightUploads = true

        if let supportedLoraRanks = supportedLoraRanks {
            llmOptions.supportedLoraRanks = supportedLoraRanks
        }

        if maxNumImages > 0 {
            llmOptions.maxImages = maxNumImages
        }

        self.inference = try LlmInference(options: llmOptions)
    }

    // Access to metrics
    var metrics: LlmInference.Metrics {
        return inference.metrics
    }
}

final class InferenceSession {
    private let session: LlmInference.Session

    init(inference: LlmInference,
         temperature: Float,
         randomSeed: Int,
         topk: Int,
         topP: Double? = nil,
         loraPath: String? = nil,
         enableVisionModality: Bool = false) throws {

        let options = LlmInference.Session.Options()
        options.temperature = temperature
        options.randomSeed = randomSeed
        options.topk = topk

        if let topP = topP {
            options.topp = Float(topP)
        }

        if let loraPath = loraPath {
            options.loraPath = loraPath
        }

        options.enableVisionModality = enableVisionModality

        // Initialize session with proper error handling for Gemma 3n
        do {
            let newSession = try LlmInference.Session(llmInference: inference, options: options)
            // Force initial token processing to ensure input*pos is properly set
            _ = try newSession.sizeInTokens(text: " ")
            self.session = newSession
        } catch {
            // Fallback: retry with minimal configuration for Gemma 3n compatibility
            let fallbackOptions = LlmInference.Session.Options()
            fallbackOptions.temperature = temperature
            fallbackOptions.randomSeed = randomSeed
            fallbackOptions.topk = topk
            fallbackOptions.enableVisionModality = enableVisionModality

            if let topP = topP {
                fallbackOptions.topp = Float(topP)
            }
            if let loraPath = loraPath {
                fallbackOptions.loraPath = loraPath
            }
            self.session = try LlmInference.Session(llmInference: inference, options: fallbackOptions)
        }
    }

    func sizeInTokens(prompt: String) throws -> Int {
        return try session.sizeInTokens(text: prompt)
    }

    func addQueryChunk(prompt: String) throws {
        print("[NATIVE LOG] ADD CHUNK  ...  \(prompt)")
        try session.addQueryChunk(inputText: prompt)
    }

    func addImage(image: CGImage) throws {
        print("[NATIVE LOG] 🖼️ Adding image to session (size: \(image.width)x\(image.height))")
        try session.addImage(image: image)
        print("[NATIVE LOG] 🖼️ Image added successfully to MediaPipe session")
    }

    // Clone session (GPU models only)
    func clone() throws -> InferenceSession {
        let clonedSession = try session.clone()
        return InferenceSession(wrapping: clonedSession)
    }

    // Private initializer for wrapping existing session (used by clone)
    private init(wrapping session: LlmInference.Session) {
        self.session = session
    }

    func generateResponse(prompt: String? = nil) throws -> String {
        if let prompt = prompt {
            print("[NATIVE LOG] ADD CHUNK XX ...  \(prompt)")
            try session.addQueryChunk(inputText: prompt)
        }
        print("[NATIVE LOG] 🔄 SYNC: About to generate response from MediaPipe")
        print("[NATIVE LOG] 🔄 SYNC: Session metrics before generation: \(session.metrics)")
        let response = try session.generateResponse()
        print("[NATIVE LOG] 🔄 SYNC: Raw response from LlmInference (\(response.count) chars): \(response)")
        print("[NATIVE LOG] 🔄 SYNC: Session metrics after generation: \(session.metrics)")
        return response
    }

    @available(iOS 13.0.0, *)
    func generateResponseAsync(prompt: String? = nil) throws -> AsyncThrowingStream<String, any Error> {
        print("[NATIVE LOG] 🔄 ASYNC: generateResponseAsync called with prompt: \(prompt ?? "nil")")
        if let prompt = prompt {
            print("[NATIVE LOG] 🔄 ASYNC: Adding prompt chunk: \(prompt)")
            try session.addQueryChunk(inputText: prompt)
        }
        print("[NATIVE LOG] 🔄 ASYNC: Session metrics before generation: \(session.metrics)")
        print("[NATIVE LOG] 🔄 ASYNC: Starting async generation...")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    print("[NATIVE LOG] 🔄 ASYNC: Entering async stream iteration")
                    var tokenCount = 0
                    var fullResponse = ""
                    for try await partialResult in session.generateResponseAsync() {
                        tokenCount += 1
                        fullResponse += partialResult
                        print("[NATIVE LOG] 🔄 ASYNC: Token #\(tokenCount): '\(partialResult)'")
                        continuation.yield(partialResult)
                    }
                    print("[NATIVE LOG] 🔄 ASYNC: All tokens generated, total: \(tokenCount) tokens")
                    print("[NATIVE LOG] 🔄 ASYNC: Full response (\(fullResponse.count) chars): \(fullResponse)")
                    print("[NATIVE LOG] 🔄 ASYNC: Session metrics after generation: \(session.metrics)")
                    continuation.finish()
                } catch {
                    print("[NATIVE LOG] 🔄 ASYNC: Error in async generation: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // Access to session metrics
    var metrics: LlmInference.Session.Metrics {
        return session.metrics
    }
}
