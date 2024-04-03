import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_gemma_platform_interface.dart';

/// An implementation of [FlutterGemmaPlatform] that uses method channels.
class MethodChannelFlutterGemma extends FlutterGemmaPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_gemma');

  @override
  Future<String?> getResponse(String prompt) async {
    return await methodChannel.invokeMethod<String>('getGemmaResponse', {'prompt': prompt});
  }
}
