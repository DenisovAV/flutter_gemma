import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'model.dart';

/// Installs the model file, reporting progress as it goes.
///
/// Nothing here is multimodal-specific: `installModel` takes the model's
/// identity (what it is) and `fromNetwork` takes the source (where the bytes
/// are). A vision model installs exactly like a text one.
class DownloadPage extends StatefulWidget {
  const DownloadPage({
    super.key,
    required this.model,
    required this.onInstalled,
    required this.onSwitch,
  });

  final ModelChoice model;

  /// Called once the model is installed, so the app can move on.
  final VoidCallback onInstalled;

  /// Asks the app for a different model, exactly as the chat's menu does.
  ///
  /// Until a model is on the device this screen IS the app, so the choice
  /// between 0.36 GB and 2.59 GB has to be reachable from here. A learner who
  /// only wants to look at pictures should never have to download an audio
  /// encoder to find that out.
  final ValueChanged<ModelChoice> onSwitch;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  int _percent = 0;
  bool _downloading = false;
  Object? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
    });

    try {
      await FlutterGemma.installModel(
        // What the model IS — used to pick the right chat template.
        modelType: widget.model.modelType,
        // Which runtime reads it. `.litertlm` routes to LiteRtLmEngine;
        // the default is `task` (MediaPipe), so this line is load-bearing.
        fileType: ModelFileType.litertlm,
      ).fromNetwork(widget.model.url).withProgress((percent) {
        if (mounted) setState(() => _percent = percent);
      }).install();

      if (mounted) widget.onInstalled();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Get the model')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.model.label, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '${widget.model.sizeLabel} — downloaded once, then it lives '
                  'on the device and runs with the network off.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_downloading) ...[
                  LinearProgressIndicator(value: _percent / 100),
                  const SizedBox(height: 8),
                  Text('$_percent%', textAlign: TextAlign.center),
                ] else
                  FilledButton(
                    onPressed: _download,
                    child: const Text('Download model'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorCard(error: _error!),
                ],
                // What each model can do, and what it costs, side by side —
                // stated before the download rather than after it.
                for (final other in Models.all)
                  if (other.fileName != widget.model.fileName) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _downloading
                          ? null
                          : () => widget.onSwitch(other),
                      child: Text(
                        'Use ${other.label} instead '
                        '(${other.sizeLabel}, ${_modalities(other)})',
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The modalities a model's WEIGHTS carry, as a phrase for a button.
String _modalities(ModelChoice model) =>
    switch ((model.supportsImage, model.supportsAudio)) {
      (true, true) => 'images and audio',
      (true, false) => 'images only',
      (false, true) => 'audio only',
      (false, false) => 'text only',
    };

/// Says what failed, in the plugin's own words where it has any.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The plugin reports a failed download as a typed `DownloadException`
    // wrapping a sealed `DownloadError`, so match on the type rather than
    // sniffing the message for a status code.
    final (title, body) = switch (error) {
      DownloadException(:final error) => (
        'Download failed',
        error.toUserMessage(),
      ),
      _ => ('Download failed', '$error'),
    };

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
