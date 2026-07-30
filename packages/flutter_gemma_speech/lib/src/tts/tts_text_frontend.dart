/// Text-frontend seam: resolves the pipeline-specific frontend (currently
/// only Matcha-CFM's `MatchaTextFrontend`) from a [TtsModelProfile]. The
/// analog of STT's tokenizer seam — `TtsCore` (Task 2.3) only ever talks to
/// this interface, never to a concrete frontend class.
library;

import '../model/tts_model_profile.dart';
import 'matcha_text_frontend.dart';
import 'tts_frontend_input.dart';

/// Resolves an out-of-dictionary word to its IPA transcription via a neural
/// G2P model (`TtsCore.neuralG2p`, Task 7), wired in by the worker (Task 11).
/// A frontend built without a resolver still throws on OOV.
typedef NeuralG2pResolver = String Function(String word);

/// text -> `TtsCore`-ready frontend input, dispatched by
/// [TtsModelProfile.pipeline]. No FFI, pure Dart.
abstract class TtsTextFrontend {
  /// text -> frontend input (symbol embeddings + mask + real length).
  MatchaFrontendInput encode(String chunk);

  /// Load the frontend for [profile], resolving artifact paths from
  /// [paths] (keyed by the profile's file-role names, e.g.
  /// `paths[profile.configFile]`).
  static Future<TtsTextFrontend> load(
    TtsModelProfile profile,
    Map<String, String> paths, {
    NeuralG2pResolver? neuralG2p,
  }) => switch (profile.pipeline) {
    TtsPipelineKind.matchaCfm => MatchaTextFrontend.load(
      profile,
      paths,
      neuralG2p: neuralG2p,
    ),
  };
}
