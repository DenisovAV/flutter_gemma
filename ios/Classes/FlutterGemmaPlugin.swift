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

    // Embedding-related properties
    private var embeddingWrapper: GemmaEmbeddingWrapper?

    // VectorStore property
    private var vectorStore: VectorStore?

    func createModel(
        maxTokens: Int64,
        modelPath: String,
        loraRanks: [Int64]?,
        preferredBackend: PreferredBackend?,
        maxNumImages: Int64?,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.model = try InferenceModel(
                    modelPath: modelPath,
                    maxTokens: Int(maxTokens),
                    supportedLoraRanks: loraRanks?.map(Int.init),
                    maxNumImages: Int(maxNumImages ?? 0)
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
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
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
                    topk: Int(topK),
                    topP: topP,
                    loraPath: loraPath,
                    enableVisionModality: enableVisionModality ?? false
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
        completion(.failure(PigeonError(
            code: "stop_not_supported", 
            message: "Stop generation is not supported on iOS platform yet", 
            details: nil
        )))
    }

    // MARK: - RAG Methods (iOS Implementation)
    
    func createEmbeddingModel(modelPath: String, tokenizerPath: String, preferredBackend: PreferredBackend?, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[PLUGIN] Creating embedding model")
        print("[PLUGIN] Model path: \(modelPath)")
        print("[PLUGIN] Tokenizer path: \(tokenizerPath)")
        print("[PLUGIN] Preferred backend: \(String(describing: preferredBackend))")

        // Convert PreferredBackend to useGPU boolean
        let useGPU = preferredBackend == .gpu || preferredBackend == .gpuFloat16 || preferredBackend == .gpuMixed || preferredBackend == .gpuFull

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create embedding wrapper instance (like Android GemmaEmbeddingModel)
                self.embeddingWrapper = try GemmaEmbeddingWrapper(
                    modelPath: modelPath,
                    tokenizerPath: tokenizerPath,
                    useGPU: useGPU
                )

                // Initialize the wrapper
                try self.embeddingWrapper?.initialize()

                DispatchQueue.main.async {
                    print("[PLUGIN] Embedding wrapper created successfully")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to create embedding model: \(error)")
                    completion(.failure(PigeonError(
                        code: "EmbeddingCreationFailed",
                        message: "Failed to create embedding model: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }
    
    func closeEmbeddingModel(completion: @escaping (Result<Void, Error>) -> Void) {
        print("[PLUGIN] Closing embedding model")

        DispatchQueue.global(qos: .userInitiated).async {
            // Close and release embedding wrapper
            self.embeddingWrapper?.close()
            self.embeddingWrapper = nil

            DispatchQueue.main.async {
                print("[PLUGIN] Embedding model closed successfully")
                completion(.success(()))
            }
        }
    }
    
    func generateEmbeddingFromModel(text: String, completion: @escaping (Result<[Double], Error>) -> Void) {
        print("[PLUGIN] Generating embedding for text: \(text)")

        guard let embeddingWrapper = embeddingWrapper else {
            completion(.failure(PigeonError(
                code: "EmbeddingModelNotInitialized",
                message: "Embedding model not initialized. Call createEmbeddingModel first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // ⚠️ FIX: Use embedDirect to avoid double prefix
                // embedDirect() only adds prefix once (in cached tokens)
                let doubleEmbeddings = try embeddingWrapper.embedDirect(text: text)

                DispatchQueue.main.async {
                    print("[PLUGIN] Generated embedding with \(doubleEmbeddings.count) dimensions")
                    completion(.success(doubleEmbeddings))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to generate embedding: \(error)")
                    completion(.failure(PigeonError(
                        code: "EmbeddingGenerationFailed",
                        message: "Failed to generate embedding: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func generateEmbeddingsFromModel(texts: [String], completion: @escaping (Result<[Any?], Error>) -> Void) {
        print("[PLUGIN] Generating embeddings for \(texts.count) texts")

        guard let embeddingWrapper = embeddingWrapper else {
            completion(.failure(PigeonError(
                code: "EmbeddingModelNotInitialized",
                message: "Embedding model not initialized. Call createEmbeddingModel first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var embeddings: [[Double]] = []
                for text in texts {
                    // ⚠️ FIX: Use embedDirect to avoid double prefix
                    let embedding = try embeddingWrapper.embedDirect(text: text)
                    embeddings.append(embedding)
                }

                DispatchQueue.main.async {
                    print("[PLUGIN] Generated \(embeddings.count) embeddings")
                    // Convert to [Any?] for pigeon compatibility (deep cast on Dart side)
                    completion(.success(embeddings as [Any?]))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to generate embeddings: \(error)")
                    completion(.failure(PigeonError(
                        code: "EmbeddingGenerationFailed",
                        message: "Failed to generate embeddings: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func getEmbeddingDimension(completion: @escaping (Result<Int64, Error>) -> Void) {
        print("[PLUGIN] Getting embedding dimension")

        guard let embeddingWrapper = embeddingWrapper else {
            completion(.failure(PigeonError(
                code: "EmbeddingModelNotInitialized",
                message: "Embedding model not initialized. Call createEmbeddingModel first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Generate a small test embedding to get dimension
                // ⚠️ FIX: Use embedDirect to avoid double prefix
                let testEmbedding = try embeddingWrapper.embedDirect(text: "test")
                let dimension = Int64(testEmbedding.count)

                DispatchQueue.main.async {
                    print("[PLUGIN] Embedding dimension: \(dimension)")
                    completion(.success(dimension))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to get embedding dimension: \(error)")
                    completion(.failure(PigeonError(
                        code: "EmbeddingDimensionFailed",
                        message: "Failed to get embedding dimension: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }
    
    // MARK: - RAG VectorStore Methods (iOS Implementation)

    func initializeVectorStore(databasePath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[PLUGIN] Initializing vector store at: \(databasePath)")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create new VectorStore instance
                self.vectorStore = VectorStore()

                // Initialize with database path
                try self.vectorStore?.initialize(databasePath: databasePath)

                DispatchQueue.main.async {
                    print("[PLUGIN] Vector store initialized successfully")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to initialize vector store: \(error)")
                    completion(.failure(PigeonError(
                        code: "VectorStoreInitFailed",
                        message: "Failed to initialize vector store: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func addDocument(id: String, content: String, embedding: [Double], metadata: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[PLUGIN] Adding document: \(id)")

        guard let vectorStore = vectorStore else {
            completion(.failure(PigeonError(
                code: "VectorStoreNotInitialized",
                message: "Vector store not initialized. Call initializeVectorStore first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try vectorStore.addDocument(
                    id: id,
                    content: content,
                    embedding: embedding,
                    metadata: metadata
                )

                DispatchQueue.main.async {
                    print("[PLUGIN] Document added successfully")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to add document: \(error)")
                    completion(.failure(PigeonError(
                        code: "AddDocumentFailed",
                        message: "Failed to add document: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func searchSimilar(queryEmbedding: [Double], topK: Int64, threshold: Double, completion: @escaping (Result<[RetrievalResult], Error>) -> Void) {
        print("[PLUGIN] Searching similar documents (topK: \(topK), threshold: \(threshold))")

        guard let vectorStore = vectorStore else {
            completion(.failure(PigeonError(
                code: "VectorStoreNotInitialized",
                message: "Vector store not initialized. Call initializeVectorStore first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let results = try vectorStore.searchSimilar(
                    queryEmbedding: queryEmbedding,
                    topK: Int(topK),
                    threshold: threshold
                )

                DispatchQueue.main.async {
                    print("[PLUGIN] Found \(results.count) similar documents")
                    completion(.success(results))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Search failed: \(error)")
                    completion(.failure(PigeonError(
                        code: "SearchFailed",
                        message: "Search failed: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func getVectorStoreStats(completion: @escaping (Result<VectorStoreStats, Error>) -> Void) {
        print("[PLUGIN] Getting vector store stats")

        guard let vectorStore = vectorStore else {
            completion(.failure(PigeonError(
                code: "VectorStoreNotInitialized",
                message: "Vector store not initialized. Call initializeVectorStore first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let stats = try vectorStore.getStats()

                DispatchQueue.main.async {
                    print("[PLUGIN] Vector store stats: \(stats.documentCount) documents, \(stats.vectorDimension)D")
                    completion(.success(stats))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to get stats: \(error)")
                    completion(.failure(PigeonError(
                        code: "GetStatsFailed",
                        message: "Failed to get stats: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func clearVectorStore(completion: @escaping (Result<Void, Error>) -> Void) {
        print("[PLUGIN] Clearing vector store")

        guard let vectorStore = vectorStore else {
            completion(.failure(PigeonError(
                code: "VectorStoreNotInitialized",
                message: "Vector store not initialized. Call initializeVectorStore first.",
                details: nil
            )))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try vectorStore.clear()

                DispatchQueue.main.async {
                    print("[PLUGIN] Vector store cleared successfully")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    print("[PLUGIN] Failed to clear vector store: \(error)")
                    completion(.failure(PigeonError(
                        code: "ClearFailed",
                        message: "Failed to clear vector store: \(error.localizedDescription)",
                        details: nil
                    )))
                }
            }
        }
    }

    func closeVectorStore(completion: @escaping (Result<Void, Error>) -> Void) {
        print("[PLUGIN] Closing vector store")

        DispatchQueue.global(qos: .userInitiated).async {
            self.vectorStore?.close()
            self.vectorStore = nil

            DispatchQueue.main.async {
                print("[PLUGIN] Vector store closed successfully")
                completion(.success(()))
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