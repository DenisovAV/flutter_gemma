import Foundation

@available(iOS 13.0, *)
class InferenceController {

    public private(set) var eventStream: AsyncStream<Result<String?, Error>>!
    private var continuation: AsyncStream<Result<String?, Error>>.Continuation?
    
    private var inferenceModel: InferenceModel?
    private var temperature: Float
    private var randomSeed: Int
    private var topK: Int
    private var loraPath: String?
    
    private var inferenceSession: InferenceSession?
    
    
    init(maxTokens: Int, temperature: Float, randomSeed: Int, topK: Int, loraPath: String? = nil) throws {
        self.inferenceModel = try InferenceModel(maxTokens: maxTokens)
        self.temperature = temperature
        self.topK = topK
        self.randomSeed = randomSeed
        self.loraPath = loraPath
        
        self.eventStream = AsyncStream { continuation in
            self.continuation = continuation
        }
    }
        
    func sendMesssage(_ text: String) throws -> String {
        inferenceSession = try InferenceSession(inference: inferenceModel!.inference, temperature: temperature, randomSeed: randomSeed, topK: topK)
        let response = try inferenceSession!.generateResponse(prompt: text)
        return response
    }
    
    
    func sendMesssageAsync(_ text: String) async throws {
        inferenceSession = try InferenceSession(inference: inferenceModel!.inference, temperature: temperature, randomSeed: randomSeed, topK: topK)
        let responseStream = try inferenceSession!.generateResponseAsync(prompt: text)
        Task.detached {
            [weak self] in
            guard let self = self else { 
                return }
            do {
                for try await token in responseStream {
                    self.continuation?.yield(.success(token))
                }
                
                self.continuation?.yield(.success(nil))
            } catch {
                self.continuation?.yield(.failure(error))
            }
        }
    }
    
    func finishStream() {
        continuation?.finish()
    }
}
