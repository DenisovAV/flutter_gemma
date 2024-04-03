import Flutter
import UIKit

public class FlutterGemmaPlugin: NSObject, FlutterPlugin {
   
  private var inferenceModel: InferenceModel?
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_gemma", binaryMessenger: registrar.messenger())
    let instance = FlutterGemmaPlugin()
    instance.inferenceModel = InferenceModel()
    registrar.addMethodCallDelegate(instance, channel: channel)
      
  }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getGemmaResponse", let prompt = call.arguments as? [String: Any], let text = prompt["prompt"] as? String {
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
            result(FlutterMethodNotImplemented)
        }
    }
}
