import Flutter
import UIKit

public class FlutterGemmaPlugin: NSObject, FlutterPlugin {
   
    private var inferenceModel: InferenceModel?

    // This static function correctly initializes the plugin with the Flutter engine
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_gemma", binaryMessenger: registrar.messenger())
        let instance = FlutterGemmaPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // This method correctly handles method calls from Flutter
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            if let prompt = call.arguments as? [String: Any], let maxTokens = prompt["maxTokens"] as? Int {
                inferenceModel = InferenceModel(maxTokens: maxTokens)
                result(nil) // Send success indication with no specific return value
            } else {
                result(FlutterError(code: "BAD_ARGS", message: "Bad arguments for 'init' method", details: nil))
            }
        case "getGemmaResponse":
            if let prompt = call.arguments as? [String: Any], let text = prompt["prompt"] as? String {
                do {
                    if let response = try inferenceModel?.generateResponse(prompt: text) {
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
