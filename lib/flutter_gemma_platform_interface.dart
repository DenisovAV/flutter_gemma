import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_gemma_method_channel.dart';

abstract class Gemma extends PlatformInterface {
  /// Constructs a FlutterGemmaPlatform.
  Gemma() : super(token: _token);

  static final Object _token = Object();

  static Gemma _instance = MethodChannelFlutterGemma();

  /// The default instance of [Gemma] to use.
  ///
  /// Defaults to [MethodChannelFlutterGemma].
  static Gemma get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [Gemma] when
  /// they register themselves.
  static set instance(Gemma instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init({int maxTokens = 1024}) async {
    await MethodChannelFlutterGemma().init(maxTokens: maxTokens);
  }

  Future<String?> getResponse({required String prompt}) async {
    final version = await MethodChannelFlutterGemma().getResponse(prompt: prompt);
    return version;
  }
}
