@JS()
library llm_inference;

import 'dart:js_interop';

extension type FilesetResolver._(JSObject _) implements JSObject {
  external static JSPromise<FilesetResolver> forGenAiTasks(JSString path);
}

extension type LlmInference._(JSObject _) implements JSObject {
  external static JSPromise<LlmInference> createFromOptions(
    FilesetResolver fileset,
    LlmInferenceOptions options,
  );
  external JSPromise<JSString> generateResponse(
    JSString text,
    JSFunction? callback, // Function(String, bool)?
  );
  external JSNumber sizeInTokens(JSString text);
  external JSPromise addQueryChunk(JSString text);
}

@JS()
@anonymous
@staticInterop
class LlmInferenceOptions {
  external factory LlmInferenceOptions({
    required LlmInferenceBaseOptions baseOptions,
    int maxTokens = 1024,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    double temperature = 1.0,
    JSInt32Array? supportedLoraRanks,
    String? loraPath,
  });
}

@JS()
@anonymous
@staticInterop
class LlmInferenceBaseOptions {
  external factory LlmInferenceBaseOptions({
    required String? modelAssetPath,
  });
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
    final response = await (_inference
        .generateResponse(
          fullPrompt.toJS,
          callback == null
              ? null
              : (JSString partial, JSAny complete) {
                  callback.call(partial.toDart, complete.parseBool());
                }.toJS,
        )
        .toDart);
    return response.toDart;
  }
}

extension JSAnyExt on JSAny {
  bool parseBool() {
    if (isA<JSBoolean>()) {
      return (this as JSBoolean).toDart;
    }
    if (isA<JSNumber>()) {
      return (this as JSNumber).toDartInt == 1;
    }
    return false;
  }
}
