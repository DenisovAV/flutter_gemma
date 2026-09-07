import 'package:flutter/foundation.dart' show kIsWeb;

import 'model.dart';

/// One modality, answered from BOTH sides.
///
/// A model that accepts audio does not mean this platform will deliver it,
/// and a platform that can record does not mean the model can hear. So the
/// app asks both questions, and — when the answer is no — says which one said
/// it. A single `bool canSendAudio` cannot do that: it collapses two
/// independent facts into one, and the user is left staring at a greyed-out
/// microphone with no idea whether the app is broken, the model is wrong, or
/// this is simply not a place where audio works.
class Capability {
  const Capability({
    required this.byModel,
    required this.byPlatform,
    required this.modelReason,
    required this.platformReason,
  });

  /// Can the weights take this input at all?
  final bool byModel;

  /// Will this platform actually carry it to them?
  final bool byPlatform;

  /// Why [byModel] is false. Read only when it is.
  final String modelReason;

  /// Why [byPlatform] is false. Read only when it is.
  final String platformReason;

  bool get available => byModel && byPlatform;

  /// Which side said no, and why. Null when both said yes.
  ///
  /// Both can refuse at once — a text-only model in a browser — and then the
  /// user deserves both halves, because fixing one changes nothing.
  String? get blockedBecause => switch ((byModel, byPlatform)) {
    (true, true) => null,
    (false, true) => modelReason,
    (true, false) => platformReason,
    (false, false) => '$modelReason, and $platformReason',
  };
}

/// What the platform will carry, before any model is involved.
///
/// This is the half of the question a model cannot answer for you, and in
/// this codelab it is the only half that ever says no — Gemma 4 E2B has both
/// encoders everywhere it runs.
abstract final class PlatformSupport {
  /// Image input reaches the model on all five native platforms — Android,
  /// iOS, macOS, Windows and Linux.
  ///
  /// Not on the web: `flutter_gemma_litertlm`'s browser arm runs the upstream
  /// `@litert-lm/core` package, whose JS API exposes no vision executor, so
  /// image bytes are **dropped with a debug warning** rather than refused.
  /// That is the worst failure mode a modality can have — the model answers,
  /// fluently and confidently, about a picture it never received — which is
  /// exactly why the app asks this before it sends anything.
  static bool get image => !kIsWeb;

  static const imageBlockedReason =
      'this platform has no image input '
      '(the browser runtime exposes no vision executor)';

  /// Audio input works on Android, on a real iPhone or iPad, and on all three
  /// desktops through the `.litertlm` engine. Not on the web, for the same
  /// reason images are not: the browser runtime exposes no audio executor
  /// either, and the bytes are dropped just as quietly.
  ///
  /// The iOS **Simulator** is the case this flag deliberately does not try to
  /// cover: nothing in Dart distinguishes it from a device, and it fails
  /// earlier than this anyway — it is CPU-only, and a 2.59 GB model does not
  /// load. The app finds that out the honest way, from the microphone probe
  /// in `chat_page.dart` or from a load error.
  static bool get audio => !kIsWeb;

  static const audioBlockedReason =
      'this platform has no audio input '
      '(the browser runtime exposes no audio executor)';
}

/// Can this app send an image right now, with this model, on this device?
Capability imageCapability(ModelChoice model) => Capability(
  byModel: model.supportsImage,
  byPlatform: PlatformSupport.image,
  modelReason: '${model.label} has no vision encoder',
  platformReason: PlatformSupport.imageBlockedReason,
);

/// Can this app send a recording right now, with this model, on this device?
Capability audioCapability(ModelChoice model) => Capability(
  byModel: model.supportsAudio,
  byPlatform: PlatformSupport.audio,
  modelReason: '${model.label} has no audio encoder',
  platformReason: PlatformSupport.audioBlockedReason,
);
