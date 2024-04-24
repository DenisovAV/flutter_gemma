import Foundation
import MediaPipeTasksGenAI

final class InferenceModel {
    private var inference: LlmInference!

    init(maxTokens: Int, temperature: Float, randomSeed: Int, topK: Int) {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = documentDirectory.appendingPathComponent("model.bin").path

        let llmOptions = LlmInference.Options(modelPath: filePath)
        llmOptions.maxTokens = maxTokens
        llmOptions.temperature = temperature
        llmOptions.randomSeed = randomSeed
        llmOptions.topk = topK
        self.inference = LlmInference(options: llmOptions)
    }

    func generateResponse(prompt: String) throws -> String {
        return try inference.generateResponse(inputText: prompt)
    }
    
    func generateResponseAsync(prompt: String, progress: @escaping (_ partialResponse: String?, _ error: Error?) -> Void, completion: @escaping (() -> Void)) throws {
        do {
            try inference.generateResponseAsync(inputText: prompt, progress: progress, completion: completion)
        } catch {
            throw error
        }
    }
}
