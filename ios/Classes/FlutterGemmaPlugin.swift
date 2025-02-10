import Flutter
import UIKit

@available(iOS 13.0, *)
public class FlutterGemmaPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
      let platformService = PlatformServiceImpl()
      PlatformServiceSetup.setUp(binaryMessenger: registrar.messenger(), api: platformService)

      let eventChannel = FlutterEventChannel(
        name: "flutter_gemma_stream", binaryMessenger: registrar.messenger())
      eventChannel.setStreamHandler(platformService)
  }
}

class PlatformServiceImpl : NSObject, PlatformService, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var model: InferenceModel?
    private var session: InferenceSession?
    
    func createModel(maxTokens: Int64, modelPath: String, loraRanks: [Int64]?, completion: @escaping (Result<Void, any Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.model = try InferenceModel(modelPath: modelPath, maxTokens: Int(maxTokens), supportedLoraRanks: loraRanks?.map(Int.init))
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func closeModel(completion: @escaping (Result<Void, any Error>) -> Void) {
        model = nil
        completion(.success(()))
    }
    
    func createSession(temperature: Double, randomSeed: Int64, loraPath: String?, topK: Int64, completion: @escaping (Result<Void, any Error>) -> Void) {
        guard let inference = model?.inference else {
            completion(.failure(PigeonError(code: "Inference model not created", message: nil, details: nil)))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let newSession = try InferenceSession(
                    inference: inference,
                    temperature: Float(temperature),
                    randomSeed: Int(randomSeed),
                    topK: Int(topK),
                    loraPath: loraPath
                )
                
                DispatchQueue.main.async {
                    self.session = newSession
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func closeSession(completion: @escaping (Result<Void, any Error>) -> Void) {
        session = nil
        completion(.success(()))
    }
    
    func generateResponse(prompt: String, completion: @escaping (Result<String, any Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if let session = self.session {
                    let response = try session.generateResponse(prompt: prompt)
                    DispatchQueue.main.async {
                        completion(.success(response))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func generateResponseAsync(prompt: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if let session = self.session, let eventSink = self.eventSink {
                    let stream = try session.generateResponseAsync(prompt: prompt)
                    Task.detached {
                        [weak self] in
                        guard let self = self else { return }
                        do {
                            for try await token in stream {
                                DispatchQueue.main.async {
                                    eventSink(token)
                                }
                            }
                            DispatchQueue.main.async {
                                eventSink(FlutterEndOfEventStream)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                eventSink(FlutterError(code: error.localizedDescription, message: nil, details: nil))
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
