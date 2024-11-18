import Flutter
import UIKit

@available(iOS 13.0, *)
public class FlutterGemmaPlugin: NSObject, FlutterPlugin {
    private var inferenceController: InferenceController?
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
    @MainActor public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            if let arguments = call.arguments as? [String: Any], let maxTokens = arguments["maxTokens"] as? Int, let temperature = arguments["temperature"] as? Float, let randomSeed = arguments["randomSeed"] as? Int, let topK = arguments["topK"] as? Int {
                do {
                    inferenceController = try InferenceController(maxTokens: maxTokens, temperature: temperature, randomSeed: randomSeed, topK: topK)
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
                    if let response = try inferenceController?.sendMesssage(prompt) {
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
                Task.detached {
                    do {
                        try await self.inferenceController?.sendMesssageAsync(prompt)
                        DispatchQueue.main.async {
                            result(nil)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "ERROR", message: "Failed to generate response: \(error.localizedDescription)", details: nil))
                        }
                    }
                }
                
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments provided", details: nil))
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

@available(iOS 13.0, *)
extension FlutterGemmaPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        
        if let viewModel = inferenceController {
            Task {
                for await result in viewModel.eventStream {

                    DispatchQueue.main.async {
                        switch result {
                        case .success(let token):
                            events(token)
                        case .failure(let error):
                            events(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
                            events(nil)
                        }
                    }
                }
            }
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
