import Foundation
import MediaPipeTasksGenAI
import MediaPipeTasksGenAIC


struct InferenceModel {
    private(set) var inference: LlmInference

    init(modelPath: String, maxTokens: Int, supportedLoraRanks: [Int]?) throws {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = documentDirectory.appendingPathComponent("model.bin").path

        let llmOptions = LlmInference.Options(modelPath: filePath)
        llmOptions.maxTokens = maxTokens
        llmOptions.waitForWeightUploads = true
        if let supportedLoraRanks = supportedLoraRanks {
          llmOptions.supportedLoraRanks = supportedLoraRanks
        }
        self.inference = try LlmInference(options: llmOptions)
    }
}

final class InferenceSession {
    private let session: LlmInference.Session

    init(inference: LlmInference, temperature: Float, randomSeed: Int, topK: Int, loraPath: String? = nil) throws {
        let options = LlmInference.Session.Options()
        options.temperature = temperature
        options.randomSeed = randomSeed
        options.topk = topK
        self.session = try LlmInference.Session(llmInference: inference, options: options)
    }

    func sizeInTokens(prompt: String) throws -> Int {
        return try session.sizeInTokens(inputText: prompt)
    }

    func addQueryChunk(prompt: String) throws {
        try session.addQueryChunk(inputText: prompt)
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
}
