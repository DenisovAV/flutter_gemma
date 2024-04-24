import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_gemma.dart';

/// An implementation of [Gemma] that uses method channels.
class GemmaMobile extends Gemma {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_gemma');

  @visibleForTesting
  final eventChannel = const EventChannel('flutter_gemma_stream');

  bool _initialized = false;

  @override
  Future<void> init({
    int maxTokens = 1024,
    temperature = 1.0,
    randomSeed = 1,
    topK = 1,
  }) async {
    final result = await methodChannel.invokeMethod<bool>(
          'init',
          {
            'maxTokens': maxTokens,
            'temperature': temperature,
            'randomSeed': randomSeed,
            'topK': topK
          },
        ) ??
        false;
    if (result) {
      _initialized = true;
    }
  }

  @override
  Future<String?> getResponse({required String prompt}) async {
    if (_initialized) {
      return await methodChannel.invokeMethod<String>('getGemmaResponse', {'prompt': prompt});
    } else {
      return 'Gemma is not initialized yet';
    }
  }

  @override
  Stream<String?> getResponseAsync({required String prompt}) {
    if (_initialized) {
      methodChannel.invokeMethod('getGemmaResponseAsync', {'prompt': prompt});
      return eventChannel.receiveBroadcastStream().map<String?>((event) => event as String?);
    } else {
      throw Exception('Gemma is not initialized yet');
    }
  }
}
