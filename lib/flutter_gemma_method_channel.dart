import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_gemma.dart';

/// An implementation of [Gemma] that uses method channels.
class MethodChannelFlutterGemma extends Gemma {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_gemma');

  bool _initialized = false;

  @override
  Future<void> init({int maxTokens = 1024}) async {
    await methodChannel.invokeMethod<void>('init', {'maxTokens': maxTokens});
    _initialized = true;
  }

  @override
  Future<String?> getResponse({required String prompt}) async {
    if (_initialized) {
      return await methodChannel.invokeMethod<String>('getGemmaResponse', {'prompt': prompt});
    } else {
      return 'Gemma is not initialized yet';
    }
  }
}
