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
        try session.addQueryChunk(inputText: prompt)
    }

    func addImage(image: CGImage) throws {
        try session.addImage(image: image)
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
            try session.addQueryChunk(inputText: prompt)
        }
        return try session.generateResponse()
    }

    @available(iOS 13.0.0, *)
    func generateResponseAsync(prompt: String? = nil) throws -> AsyncThrowingStream<String, any Error> {
        if let prompt = prompt {
            try session.addQueryChunk(inputText: prompt)
        }
        return session.generateResponseAsync()
    }

    // Access to session metrics
    var metrics: LlmInference.Session.Metrics {
        return session.metrics
    }
}