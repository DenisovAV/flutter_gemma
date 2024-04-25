@JS()
library llm_inference;

import 'package:js/js.dart';

@JS()
class FilesetResolver {
  external static Future<FilesetResolver> forGenAiTasks(String path);
}

@JS()
class LlmInference {
  external static Future<LlmInference> createFromOptions(FilesetResolver fileset, dynamic options);
  external Future<String> generateResponse(String text, Function(String, bool)? callback);
}
