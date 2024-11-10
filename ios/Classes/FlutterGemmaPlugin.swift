import Flutter
import UIKit

public class FlutterGemmaPlugin: NSObject, FlutterPlugin {
   
    private var inferenceModel: InferenceModel?
    private var eventSink: FlutterEventSink?

    // This static function correctly initializes the plugin with the Flutter engine
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_gemma", binaryMessenger: registrar.messenger())
        let instance = FlutterGemmaPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let eventChannel = FlutterEventChannel(name: "flutter_gemma_stream", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }

    // This method correctly handles method calls from Flutter
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            if let arguments = call.arguments as? [String: Any], let maxTokens = arguments["maxTokens"] as? Int, let temperature = arguments["temperature"] as? Float, let randomSeed = arguments["randomSeed"] as? Int, let topK = arguments["topK"] as? Int {
                do {
                    inferenceModel = try InferenceModel(maxTokens: maxTokens, temperature: temperature, randomSeed: randomSeed, topK: topK)
                } catch {
                    result(FlutterError(code: "ERROR", message: "Failed to generate response: \(error.localizedDescription)", details: nil))
                }
                result(true)
            } else {
                result(FlutterError(code: "ERROR", message: "Failed to initialize gemma", details: nil))
            }
        case "getGemmaResponse":
            if let arguments = call.arguments as? [String: Any], let prompt = arguments["prompt"] as? String {
                do {
                    if let response = try inferenceModel?.generateResponse(prompt: prompt) {
                        result(response)
                    } else {
                        result(FlutterError(code: "UNAVAILABLE", message: "Inference model could not generate a response", details: nil))
                    }
                } catch {
                    result(FlutterError(code: "ERROR", message: "Failed to generate response: \(error.localizedDescription)", details: nil))
                }
            } else {
                result(FlutterError(code: "BAD_ARGS", message: "Bad arguments for 'getGemmaResponse' method", details: nil))
            }
        case "getGemmaResponseAsync":
            if let arguments = call.arguments as? [String: Any], let prompt = arguments["prompt"] as? String {
                do {
                    try inferenceModel?.generateResponseAsync(prompt: prompt, progress: { partialResponse, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                let errorMap: [String: Any] = [
                                    "code": "ASYNC_ERROR",
                                    "message": error.localizedDescription,
                                    "details": NSNull(),
                                ]
                                self.eventSink?(errorMap)
                            } else if let partialResponse = partialResponse {
                                self.eventSink?(partialResponse)
                            }
                        }
                    }, completion: {

                        DispatchQueue.main.async {
                            self.eventSink?(nil)
                            result(nil)
                        }
                    })
                } catch {
                    result(FlutterError(code: "ERROR", message: "Failed to get async gemma response", details: error.localizedDescription))
                }
            } else {
                result(FlutterError(code: "BAD_ARGS", message: "Bad arguments for 'getGemmaResponseAsync' method", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

extension FlutterGemmaPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
