import 'package:flutter_gemma/flutter_gemma.dart';

import 'prompt_strategy.dart';

/// Wraps an `InferenceModel` to make single-shot translation a one-call
/// operation.
///
/// The plugin already exposes the single-shot primitive
/// (`InferenceModel.createSession()`), so this is example-side glue: prompt
/// formatting + lifecycle management + a `translate()` / `translateStream()`
/// pair shaped for translator UX. Different translator bundles plug in
/// different `TranslationPromptStrategy` instances.
class TranslateRunner {
  TranslateRunner({
    required InferenceModel model,
    required TranslationPromptStrategy strategy,
  })  : _model = model,
        _strategy = strategy;

  final InferenceModel _model;
  final TranslationPromptStrategy _strategy;

  /// One-shot translation: returns the full output string once decoding
  /// completes.
  Future<String> translate({
    required String text,
    required String src,
    required String dst,
  }) async {
    final session = await _model.createSession(temperature: 0);
    try {
      await session.addQueryChunk(
        Message.text(
          text: _strategy.formatPrompt(src: src, dst: dst, text: text),
          isUser: true,
        ),
      );
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }

  /// Streaming translation: emits each generated chunk as the model decodes.
  /// Caller can cancel via the returned `Stream`'s subscription; the session
  /// is closed when the stream is done (either fully consumed or cancelled).
  Stream<String> translateStream({
    required String text,
    required String src,
    required String dst,
  }) async* {
    final session = await _model.createSession(temperature: 0);
    try {
      await session.addQueryChunk(
        Message.text(
          text: _strategy.formatPrompt(src: src, dst: dst, text: text),
          isUser: true,
        ),
      );
      yield* session.getResponseAsync();
    } finally {
      await session.close();
    }
  }
}
