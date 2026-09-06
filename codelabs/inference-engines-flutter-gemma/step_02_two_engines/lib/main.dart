import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'chat_page.dart';
import 'download_page.dart';
import 'model.dart';

/// Supplied at run time, never committed:
///   flutter run --dart-define=HF_TOKEN=hf_your_token
const _hfToken = String.fromEnvironment('HF_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Two engines, registered side by side. Each declares which file types it
  // can open; the registry picks one per model from `ModelFileType`. Nothing
  // in the chat code knows or cares which engine ends up answering.
  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine(), const BuiltInAiEngine()],
    huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
  );

  runApp(const EnginesApp());
}

class EnginesApp extends StatefulWidget {
  const EnginesApp({super.key});

  @override
  State<EnginesApp> createState() => _EnginesAppState();
}

class _EnginesAppState extends State<EnginesApp> {
  /// Which model — and therefore which engine — the app is using right now.
  ModelChoice _choice = Models.gemma3;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Engines',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      // A new key per model restarts the gate from scratch on a switch.
      home: ModelGate(
        key: ValueKey(_choice.id),
        model: _choice,
        onSwitch: (next) => setState(() => _choice = next),
      ),
    );
  }
}

/// On every cold start — and on every switch — makes sure the chosen model is
/// on the device AND is the active one.
class ModelGate extends StatefulWidget {
  const ModelGate({super.key, required this.model, required this.onSwitch});

  final ModelChoice model;
  final ValueChanged<ModelChoice> onSwitch;

  @override
  State<ModelGate> createState() => _ModelGateState();
}

class _ModelGateState extends State<ModelGate> {
  late Future<bool> _ready = _prepare();

  Future<bool> _prepare() async {
    final installed = await FlutterGemma.isModelInstalled(widget.model.id);
    // Installed is not the same as active. `install()` is idempotent, so
    // re-running it on a model that is already here costs nothing and makes
    // it the one `getActiveModel` will load.
    if (installed) await activate(widget.model);
    return installed;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data ?? false) {
          return ChatPage(
            model: widget.model,
            onSwitch: widget.onSwitch,
            onModelRemoved: () => setState(() => _ready = _prepare()),
          );
        }
        return DownloadPage(
          model: widget.model,
          onReady: () => setState(() => _ready = _prepare()),
        );
      },
    );
  }
}
