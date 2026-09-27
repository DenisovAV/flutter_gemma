import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// No-op web plugin registrant.
///
/// `flutter_gemma_builtin_ai`'s web arm is pure `dart:js_interop` (the
/// Chrome Prompt API) — no platform channel, no federated-plugin facade to
/// swap in. This class exists only so `flutter build web` generates a
/// registrant call for the package's `web:` entry in `pubspec.yaml` (which
/// is itself required because the package already declares a plugin block
/// for Android/iOS/macOS — pub.dev's web-support badge and the plugin
/// tooling both key off every platform in that block having an entry).
class FlutterGemmaBuiltInAiWeb {
  static void registerWith(Registrar registrar) {
    // Nothing to register — see class doc comment.
  }
}
