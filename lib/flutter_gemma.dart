import 'flutter_gemma_platform_interface.dart';

class FlutterGemma {
  Future<String?> getResponse(String prompt) {
    return FlutterGemmaPlatform.instance.getResponse(prompt);
  }
}
