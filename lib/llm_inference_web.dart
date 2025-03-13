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
  external Future<int> sizeInTokens(String text);
  external Future<void> addQueryChunk(String text);
}

class LlmInferenceWrapper {
  final LlmInference _inference;
  final List<String> _queryChunks = [];

  LlmInferenceWrapper(this._inference);

  void addQueryChunk(String text) {
    _queryChunks.add(text);
  }

  Future<String> generateResponse({Function(String, bool)? callback}) async {
    final String fullPrompt = _queryChunks.join(" ");
    _queryChunks.clear();
    return _inference.generateResponse(fullPrompt, callback);
  }
}
