import Foundation
import MediaPipeTasksGenAI
import MediaPipeTasksGenAIC


struct InferenceModel {
    private (set) var inference: LlmInference

    init(maxTokens: Int) throws {
        
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = documentDirectory.appendingPathComponent("model.bin").path

        let llmOptions = LlmInference.Options(modelPath: filePath)
        llmOptions.maxTokens = maxTokens
    
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

func generateResponse(prompt: String) throws -> String {
    try session.addQueryChunk(inputText: prompt)
        return try session.generateResponse()
    }

    @available(iOS 13.0.0, *)
    func generateResponseAsync(prompt: String) throws -> AsyncThrowingStream<String, any Error> {
        try session.addQueryChunk(inputText: prompt)
        return session.generateResponseAsync()
    }
}
