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
  /// Null until the startup probe has answered.
  ModelChoice? _choice;

  /// Why the app picked what it picked. Shown once in the chat so the
  /// decision is visible instead of silent.
  String? _reason;

  @override
  void initState() {
    super.initState();
    _pickAtStartup();
  }

  /// Prefer the model the OS already ships; fall back to a downloaded one.
  ///
  /// Availability is a property of the device and OS, not of the build —
  /// it has to be asked at run time, every time.
  Future<void> _pickAtStartup() async {
    final status = await BuiltInAi.availability();
    final (choice, reason) = switch (status) {
      BuiltInAiAvailability.available => (
        Models.builtIn,
        'Using the model the OS ships — nothing was downloaded.',
      ),
      BuiltInAiAvailability.downloadable ||
      BuiltInAiAvailability.downloading => (
        Models.builtIn,
        'The OS has a built-in model; it will fetch the feature once.',
      ),
      BuiltInAiAvailability.unavailableDisabled => (
        Models.gemma3,
        'Built-in AI is turned off on this device — using a downloaded model.',
      ),
      _ => (
        Models.gemma3,
        'No built-in model here ($status) — using a downloaded model.',
      ),
    };
    if (mounted) {
      setState(() {
        _choice = choice;
        _reason = reason;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    return MaterialApp(
      title: 'Engines',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: choice == null
          ? const _Probing()
          // A new key per model restarts the gate from scratch on a switch.
          : ModelGate(
              key: ValueKey(choice.id),
              model: choice,
              reason: _reason,
              onSwitch: (next) => setState(() {
                _choice = next;
                _reason = 'Switched by hand.';
              }),
            ),
    );
  }
}

/// The availability probe is bounded (it gives up after 20 s on an OS whose
/// AI stack never answers), so this screen is short-lived but not instant.
class _Probing extends StatelessWidget {
  const _Probing();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking for a built-in model…'),
          ],
        ),
      ),
    );
  }
}

/// On every cold start — and on every switch — makes sure the chosen model is
/// on the device AND is the active one.
class ModelGate extends StatefulWidget {
  const ModelGate({
    super.key,
    required this.model,
    required this.onSwitch,
    this.reason,
  });

  final ModelChoice model;
  final ValueChanged<ModelChoice> onSwitch;

  /// One line explaining the startup decision, surfaced in the chat.
  final String? reason;

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
            reason: widget.reason,
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
