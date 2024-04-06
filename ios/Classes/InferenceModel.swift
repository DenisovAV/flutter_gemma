import Foundation
import MediaPipeTasksGenAI

final class InferenceModel {
    private var inference: LlmInference!

    init(maxTokens: Int) {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = documentDirectory.appendingPathComponent("model.bin").path

        let llmOptions = LlmInference.Options(modelPath: filePath)
        llmOptions.maxTokens = maxTokens
        self.inference = LlmInference(options: llmOptions)
    }

    func generateResponse(prompt: String) throws -> String {
        return try inference.generateResponse(inputText: prompt)
    }
}
