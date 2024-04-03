import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_gemma_method_channel.dart';

abstract class FlutterGemmaPlatform extends PlatformInterface {
  /// Constructs a FlutterGemmaPlatform.
  FlutterGemmaPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterGemmaPlatform _instance = MethodChannelFlutterGemma();

  /// The default instance of [FlutterGemmaPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterGemma].
  static FlutterGemmaPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterGemmaPlatform] when
  /// they register themselves.
  static set instance(FlutterGemmaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getResponse(String prompt) async {
    final version = await MethodChannelFlutterGemma().getResponse(prompt);
    return version;
  }
}
