import 'package:flutter/foundation.dart' show kIsWeb;

import 'model.dart';

/// One modality, answered from BOTH sides.
///
/// A model that accepts audio does not mean this platform will deliver it,
/// and a platform that can record does not mean the model can hear. The app
/// has to ask both questions, and — when the answer is no — say which one
/// said it. A single `bool canSendAudio` cannot do that: it collapses two
/// independent facts into one, and the user is left staring at a greyed-out
/// button with no idea whether to change the model or change the device.
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
  /// Both sides can refuse at once — a vision-only model in a browser — and
  /// then the user deserves both halves, because fixing one changes nothing.
  String? get blockedBecause => switch ((byModel, byPlatform)) {
    (true, true) => null,
    (false, true) => modelReason,
    (true, false) => platformReason,
    (false, false) => '$modelReason, and $platformReason',
  };
}

/// What the platform will carry, before any model is involved.
///
/// This is the half of the question a model cannot answer for you.
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
      'this platform cannot carry images to the model '
      '(the browser runtime has no vision executor)';

  /// Audio input is the narrower of the two, and it is narrower for a
  /// different reason than images are.
  ///
  /// It works on Android, on a real iPhone or iPad, and on all three desktops
  /// through the `.litertlm` engine. It does not work on the web at all — the
  /// same `@litert-lm/core` limitation, one executor further along — and the
  /// bytes are dropped there in the same silent way.
  ///
  /// The iOS **Simulator** is the case this flag deliberately does not try to
  /// cover: nothing in Dart can distinguish it from a device, so the app finds
  /// out the honest way, when the microphone or the model says no. See the
  /// microphone probe in `chat_page.dart`.
  static bool get audio => !kIsWeb;

  static const audioBlockedReason =
      'this platform cannot carry audio to the model '
      '(the browser runtime has no audio executor)';
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
