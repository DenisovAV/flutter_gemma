import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_gemma_mobile.dart' if (dart.library.html) 'flutter_gemma_web.dart';

abstract class Gemma extends PlatformInterface {
  /// Constructs a FlutterGemmaPlatform.
  Gemma() : super(token: _token);

  static final Object _token = Object();

  static Gemma _instance = GemmaMobile();

  /// The default instance of [Gemma] to use.
  ///
  /// Defaults to [GemmaMobile].
  static Gemma get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [Gemma] when
  /// they register themselves.
  static set instance(Gemma instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init({
    int maxTokens = 1024,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 1,
  }) =>
      GemmaMobile().init(
        maxTokens: maxTokens,
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
      );

  Future<String?> getResponse({required String prompt}) =>
      GemmaMobile().getResponse(prompt: prompt);

  Stream<String?> getResponseAsync({required String prompt}) =>
      GemmaMobile().getResponseAsync(prompt: prompt);
}
