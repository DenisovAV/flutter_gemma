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

      // Bundled resources method channel
      let bundledChannel = FlutterMethodChannel(
        name: "flutter_gemma_bundled",
        binaryMessenger: registrar.messenger())
      bundledChannel.setMethodCallHandler { (call, result) in
        if call.method == "getBundledResourcePath" {
          guard let args = call.arguments as? [String: Any],
                let resourceName = args["resourceName"] as? String else {
            result(FlutterError(code: "INVALID_ARGS",
                               message: "resourceName is required",
                               details: nil))
            return
          }

          // Split resourceName into name and extension
          let components = resourceName.split(separator: ".")
          let name = String(components[0])
          let ext = components.count > 1 ? String(components[1]) : ""

          // Get path from Bundle.main
          if let path = Bundle.main.path(forResource: name, ofType: ext) {
            result(path)
          } else {
            result(FlutterError(code: "NOT_FOUND",
                               message: "Resource not found in bundle: \(resourceName)",
                               details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
  }
}

class PlatformServiceImpl : NSObject, PlatformService, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var model: InferenceModel?
    private var session: InferenceSession?

    // 0.15.2: embedding migrated to the shared Dart-FFI + LiteRT path
    // (see `lib/core/litert/litert_embedding_model.dart`). The pigeon
    // surface below is preserved for ABI continuity but no longer
    // backs the runtime path — Dart instantiates LitertEmbeddingModel
    // directly and never calls these methods.

    func createModel(
        maxTokens: Int64,
        modelPath: String,
        loraRanks: [Int64]?,
        preferredBackend: PreferredBackend?,
        maxNumImages: Int64?,
        supportAudio: Bool?,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.model = try InferenceModel(
                    modelPath: modelPath,
                    maxTokens: Int(maxTokens),
                    supportedLoraRanks: loraRanks?.map(Int.init),
                    maxNumImages: Int(maxNumImages ?? 0),
                    preferredBackend: preferredBackend,
                    supportAudio: supportAudio ?? false
                )
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

    func createSession(
        temperature: Double,
        randomSeed: Int64,
        topK: Int64,
        topP: Double?,
        loraPath: String?,
        enableVisionModality: Bool?,
        enableAudioModality: Bool?,
        systemInstruction: String?,
        enableThinking: Bool?,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        guard let inference = model?.inference else {
            completion(.failure(PigeonError(code: "Inference model not created", message: nil, details: nil)))
            return
        }

        if enableThinking == true {
            print("[FlutterGemma] Warning: enableThinking=true is not supported on iOS (MediaPipe). " +
                  "Use Android or Desktop with .litertlm models for Gemma 4 thinking mode.")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let newSession = try InferenceSession(
                    inference: inference,
                    temperature: Float(temperature),
                    randomSeed: Int(randomSeed),
                    topk: Int(topK),
                    topP: topP,
                    loraPath: loraPath,
                    enableVisionModality: enableVisionModality ?? false,
                    enableAudioModality: enableAudioModality ?? false
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

    func sizeInTokens(prompt: String, completion: @escaping (Result<Int64, any Error>) -> Void) {
        guard let session = session else {
            completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tokenCount = try session.sizeInTokens(prompt: prompt)
                DispatchQueue.main.async { completion(.success(Int64(tokenCount))) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func addQueryChunk(prompt: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        guard let session = session else {
            completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try session.addQueryChunk(prompt: prompt)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // Add method for adding image
    func addImage(imageBytes: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        guard let session = session else {
            completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let uiImage = UIImage(data: imageBytes.data) else {
                    DispatchQueue.main.async {
                        completion(.failure(PigeonError(code: "Invalid image data", message: "Could not create UIImage from data", details: nil)))
                    }
                    return
                }

                guard let cgImage = uiImage.cgImage else {
                    DispatchQueue.main.async {
                        completion(.failure(PigeonError(code: "Invalid image format", message: "Could not get CGImage from UIImage", details: nil)))
                    }
                    return
                }

                try session.addImage(image: cgImage)

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

    // Add audio input (supported since MediaPipe 0.10.33)
    func addAudio(audioBytes: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
        guard let session = session else {
            completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try session.addAudio(audio: audioBytes.data)
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

    func generateResponse(completion: @escaping (Result<String, any Error>) -> Void) {
        guard let session = session else {
            completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try session.generateResponse()
                DispatchQueue.main.async { completion(.success(response)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    @available(iOS 13.0, *)
    func generateResponseAsync(completion: @escaping (Result<Void, any Error>) -> Void) {
        print("[PLUGIN LOG] generateResponseAsync called")
        guard let session = session, let eventSink = eventSink else {
            print("[PLUGIN LOG] Session or eventSink not created")
            completion(.failure(PigeonError(code: "Session or eventSink not created", message: nil, details: nil)))
            return
        }
        
        print("[PLUGIN LOG] Session and eventSink available, starting generation")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("[PLUGIN LOG] Getting async stream from session")
                let stream = try session.generateResponseAsync()
                print("[PLUGIN LOG] Got stream, starting Task")
                Task.detached { [weak self] in
                    guard let self = self else { 
                        print("[PLUGIN LOG] Self is nil in Task")
                        return 
                    }
                    do {
                        print("[PLUGIN LOG] Starting to iterate over stream")
                        var tokenCount = 0
                        for try await token in stream {
                            tokenCount += 1
                            print("[PLUGIN LOG] Got token #\(tokenCount): '\(token)'")
                            DispatchQueue.main.async {
                                print("[PLUGIN LOG] Sending token to Flutter via eventSink")
                                eventSink(["partialResult": token, "done": false])
                                print("[PLUGIN LOG] Token sent to Flutter")
                            }
                        }
                        print("[PLUGIN LOG] Stream finished after \(tokenCount) tokens")
                        DispatchQueue.main.async {
                            print("[PLUGIN LOG] Sending FlutterEndOfEventStream")
                            eventSink(FlutterEndOfEventStream)
                            print("[PLUGIN LOG] FlutterEndOfEventStream sent")
                        }
                    } catch {
                        print("[PLUGIN LOG] Error in stream iteration: \(error)")
                        DispatchQueue.main.async {
                            eventSink(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
                        }
                    }
                }
                DispatchQueue.main.async {
                    print("[PLUGIN LOG] Completing with success")
                    completion(.success(()))
                }
            } catch {
                print("[PLUGIN LOG] Error creating stream: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func stopGeneration(completion: @escaping (Result<Void, any Error>) -> Void) {
        guard let session = session else {
            completion(.failure(PigeonError(code: "Session not created", message: nil, details: nil)))
            return
        }

        do {
            try session.cancelGeneration()
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    // 0.15.2: embedding pigeon methods dropped from PlatformService.
    // Dart talks to LiteRT C API directly via dart:ffi
    // (lib/core/litert/litert_embedding_model.dart).
    
    // MARK: - RAG VectorStore Methods (no-ops: VectorStore is now handled entirely in Dart via sqlite3)

    func initializeVectorStore(databasePath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func addDocument(id: String, content: String, embedding: [Double], metadata: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func searchSimilar(queryEmbedding: [Double], topK: Int64, threshold: Double, completion: @escaping (Result<[RetrievalResult], Error>) -> Void) {
        completion(.success([]))
    }

    func getVectorStoreStats(completion: @escaping (Result<VectorStoreStats, Error>) -> Void) {
        completion(.success(VectorStoreStats(documentCount: 0, vectorDimension: 0)))
    }

    func clearVectorStore(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func closeVectorStore(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func getAllDocumentsWithEmbeddings(completion: @escaping (Result<[DocumentWithEmbedding], Error>) -> Void) {
        completion(.success([]))
    }

    func getDocumentsByIds(ids: [String], completion: @escaping (Result<[RetrievalResult], Error>) -> Void) {
        completion(.success([]))
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