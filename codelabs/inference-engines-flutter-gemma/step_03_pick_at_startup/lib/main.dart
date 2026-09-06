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
    // `availability()` never throws for an OS that answers — but a plugin
    // that failed to register does, and an uncaught throw here would leave
    // the app on the probe screen forever.
    BuiltInAiAvailability status;
    try {
      status = await BuiltInAi.availability();
    } catch (_) {
      status = BuiltInAiAvailability.unavailableOther;
    }
    // The switch evaluates `Models.builtIn`, which throws where this app has
    // no built-in arm — so guard it here the way the chat page's menu does,
    // and fall through to the downloaded model.
    ModelChoice choice;
    try {
      choice = switch (status) {
        BuiltInAiAvailability.available ||
        BuiltInAiAvailability.downloadable ||
        BuiltInAiAvailability.downloading => Models.builtIn,
        _ => Models.gemma3,
      };
    } on UnsupportedError {
      choice = Models.gemma3;
    }
    if (mounted) setState(() => _choice = choice);
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
              onSwitch: (next) => setState(() => _choice = next),
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
/// ready to answer AND is the active one.
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
    if (widget.model.isBuiltIn) {
      // "Installed" is not a concept for a built-in model. The OS owns the
      // weights, nothing lands on disk, and no install record is written — so
      // `isModelInstalled` answers no forever. Ask the OS instead.
      final status = await BuiltInAi.availability();
      if (status != BuiltInAiAvailability.available) return false;
      // Ready, but not yet current: `activate` records the identity that
      // `getActiveModel` will load.
      await activate(widget.model);
      return true;
    }

    final installed = await FlutterGemma.isModelInstalled(widget.model.id);
    // For a downloaded model, installed is still not the same as active.
    // `install()` is idempotent, so re-running it on a model that is already
    // here costs nothing and makes it the one `getActiveModel` will load.
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
        if (snapshot.hasError) {
          // A FutureBuilder that ignores `hasError` renders the setup screen
          // as if nothing had gone wrong — including when the OS flipped the
          // built-in model to unavailable under the app's feet.
          return _GateError(
            error: snapshot.error!,
            onRetry: () => setState(() => _ready = _prepare()),
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
          // The same callback the chat's menu gets — see
          // `DownloadPage.onSwitch` for why the setup screen needs one too.
          onSwitch: widget.onSwitch,
        );
      },
    );
  }
}

/// Shown when the gate's own check fails, rather than falling through to the
/// setup screen as if the answer had been "not ready".
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
