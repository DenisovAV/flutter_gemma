import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_gemma.dart';

/// An implementation of [FlutterGemmaPlugin] that uses method channels.
class FlutterGemma extends FlutterGemmaPlugin {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_gemma');

  @visibleForTesting
  final eventChannel = const EventChannel('flutter_gemma_stream');

  final Completer<bool> _initCompleter = Completer<bool>();

  @override
  Future<bool> get isInitialized => _initCompleter.future;

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
    if (result && !_initCompleter.isCompleted) {
        _initCompleter.complete(true);
    }
  }

  @override
  Future<String?> getResponse({required String prompt}) async {
    if (_initCompleter.isCompleted) {
      return await methodChannel.invokeMethod<String>('getGemmaResponse', {'prompt': prompt});
    } else {
      return 'Gemma is not initialized yet';
    }
  }

  @override
  Stream<String?> getResponseAsync({required String prompt}) {
    if (_initCompleter.isCompleted) {
      methodChannel.invokeMethod('getGemmaResponseAsync', {'prompt': prompt});
      return eventChannel.receiveBroadcastStream().map<String?>((event) => event as String?);
    } else {
      throw Exception('Gemma is not initialized yet');
    }
  }
}
