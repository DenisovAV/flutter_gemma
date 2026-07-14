import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// FlutterGemmaBuiltInAiPlugin — hosts the built-in OS AI (Apple Foundation
/// Models on iOS 26+/macOS 26+) `BuiltInAiService` HostApi + the shared
/// "flutter_gemma_builtin_ai_stream" async-result `FlutterEventChannel`.
///
/// One shared Darwin source set backs both platforms; the only per-platform
/// difference is how the binary messenger is reached on the registrar
/// (`messenger()` on iOS vs the `messenger` property on macOS).
public class FlutterGemmaBuiltInAiPlugin: NSObject, FlutterPlugin {
  // Held for the lifetime of the plugin so the event-channel stream handler and
  // the pigeon HostApi share the SAME service instance.
  private static var service: BuiltInAiServiceImpl?

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif

    let service = BuiltInAiServiceImpl()
    self.service = service

    BuiltInAiServiceSetup.setUp(binaryMessenger: messenger, api: service)

    let eventChannel = FlutterEventChannel(
      name: "flutter_gemma_builtin_ai_stream",
      binaryMessenger: messenger)
    eventChannel.setStreamHandler(service)
  }
}
