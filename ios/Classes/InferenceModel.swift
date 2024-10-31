import Foundation
import MediaPipeTasksGenAI

final class InferenceModel {
    private var inference: LlmInference!
    private var session: LlmInference.Session?

    init(maxTokens: Int, temperature: Float, randomSeed: Int, topK: Int,
             numOfSupportedLoraRanks: Int? = nil,
             supportedLoraRanks: [Int]? = nil,
             loraPath: String? = nil) throws {
            
            let fileManager = FileManager.default
            let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let filePath = documentDirectory.appendingPathComponent("model.bin").path

            let llmOptions = LlmInference.Options(modelPath: filePath)
            llmOptions.maxTokens = maxTokens
            if let ranks = supportedLoraRanks {
                llmOptions.supportedLoraRanks = ranks
            }
            

            self.inference = try LlmInference(options: llmOptions)
                
            let sessionOptions = LlmInference.Session.Options()
            sessionOptions.temperature = temperature
            sessionOptions.randomSeed = randomSeed
            sessionOptions.topk = topK
            sessionOptions.loraPath = loraPath
                
            self.session = try LlmInference.Session(llmInference: inference, options: sessionOptions)
        }

    func generateResponse(prompt: String) throws -> String {
        try session?.addQueryChunk(inputText: prompt)
        return try session?.generateResponse() ?? ""
    }
    
    func generateResponseAsync(prompt: String, progress: @escaping (_ partialResponse: String?, _ error: Error?) -> Void, completion: @escaping (() -> Void)) throws {
        try session?.addQueryChunk(inputText: prompt)
        try session?.generateResponseAsync(progress: progress, completion: completion)
    }
}
