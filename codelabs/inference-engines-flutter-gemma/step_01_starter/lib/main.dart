import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'chat_page.dart';
import 'download_page.dart';
import 'model.dart';

/// Supplied at run time, never committed:
///   flutter run --dart-define=HF_TOKEN=hf_your_token
const _hfToken = String.fromEnvironment('HF_TOKEN');

/// Change this one line to run the whole app on a different model.
const _model = Models.gemma3;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Engines are fully opt-in: the core package registers none by itself.
  // Without LiteRtLmEngine here, the first model call throws a StateError
  // that tells you to add an engine package.
  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
  );

  runApp(const QuickstartApp());
}

class QuickstartApp extends StatelessWidget {
  const QuickstartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Quickstart',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const ModelGate(model: _model),
    );
  }
}

/// Asks, on every cold start, whether the model is already on disk.
///
/// Skipping this check is the classic beginner bug: the app re-downloads
/// half a gigabyte every single launch. Delete the model from the chat's
/// menu and relaunch to watch this branch flip back.
class ModelGate extends StatefulWidget {
  const ModelGate({super.key, required this.model});

  final ModelChoice model;

  @override
  State<ModelGate> createState() => _ModelGateState();
}

class _ModelGateState extends State<ModelGate> {
  late Future<bool> _installed = _check();

  Future<bool> _check() => FlutterGemma.isModelInstalled(widget.model.fileName);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _installed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data ?? false) {
          return ChatPage(
            model: widget.model,
            onModelRemoved: () => setState(() => _installed = _check()),
          );
        }
        return DownloadPage(
          model: widget.model,
          onInstalled: () => setState(() => _installed = _check()),
        );
      },
    );
  }
}
