import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'chat_page.dart';
import 'download_page.dart';
import 'model.dart';

/// The one model this codelab runs, from here to the end.
const _model = Models.gemma4;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Engines are fully opt-in: the core package registers none by itself.
  // Without LiteRtLmEngine here, the first model call throws a StateError
  // that tells you to add an engine package.
  //
  // No `huggingFaceToken:` — the model this codelab uses from Step 2 on is
  // ungated. (Step 1 inherits Gemma 3 1B from Getting Started, and that repo
  // IS behind a licence gate: it needs `--dart-define=HF_TOKEN=hf_...`.)
  //
  // Guarded, because every other failure in this app reaches the screen — the
  // gate's error card, the chat's load error, the notice line — and this is the
  // earliest one, so it is the one a learner meets first. Hot-restarting after
  // adding a plugin throws `MissingPluginException` right here; unguarded, it
  // never reaches `runApp` and the symptom is a blank window and a stack trace
  // in a console nobody is looking at.
  try {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  } catch (error) {
    runApp(_StartupFailed(error: error));
    return;
  }

  runApp(const MultimodalApp());
}

/// Shown in place of the app when `FlutterGemma.initialize` throws, so a
/// failure before the first frame is a sentence instead of a blank window.
class _StartupFailed extends StatelessWidget {
  const _StartupFailed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Multimodal',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'flutter_gemma could not start.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class MultimodalApp extends StatelessWidget {
  const MultimodalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Multimodal',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const ModelGate(model: _model),
    );
  }
}

/// Asks, on every cold start, whether the model is already installed.
///
/// `install()` is idempotent, so the bytes are only ever fetched once. What a
/// drifted id costs you is this gate: it answers "no" forever, so the app
/// shows the download screen on every launch, the "download" there finishes
/// instantly, and you land straight back here. Delete the model with the chat's
/// delete button and relaunch to watch this branch flip back.
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
        if (snapshot.hasError) {
          // A FutureBuilder that ignores `hasError` renders the download
          // screen as if nothing had gone wrong. Say what failed instead.
          return _GateError(
            error: snapshot.error!,
            onRetry: () => setState(() => _installed = _check()),
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

/// Shown when the gate's own check fails, rather than falling through to the
/// download screen as if the answer had been "no".
class _GateError extends StatelessWidget {
  const _GateError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
