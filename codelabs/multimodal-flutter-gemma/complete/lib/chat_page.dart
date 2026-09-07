import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import 'capabilities.dart';
import 'model.dart';
import 'wav.dart';

/// The recorder asks for these, and [wavFromPcm16] writes them into the
/// header. 16 kHz mono is what the model's audio front end wants; sending it
/// 44.1 kHz stereo means resampling somewhere, and the somewhere is native
/// code you cannot see.
const _sampleRate = 16000;
const _channels = 1;

/// A clip long enough to ask a question and short enough not to eat the
/// context window. Audio is not free: the encoder turns every second into
/// tokens, and they come out of the same budget as the reply.
const _maxClip = Duration(seconds: 15);

/// A chat that can carry a picture or a recording along with the question.
///
/// `generateChatResponseAsync` emits one [ModelResponse] per decoded chunk,
/// so the first words appear long before the last one is computed — the same
/// on a multimodal turn as on a text one.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.model,
    required this.onSwitch,
    required this.onModelRemoved,
  });

  final ModelChoice model;

  /// Asks the app to run a different model — and therefore to answer the
  /// model half of every capability question differently.
  final ValueChanged<ModelChoice> onSwitch;

  /// Lets the gate send the app back to the download screen.
  final VoidCallback onModelRemoved;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _turns = <_Turn>[];
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  InferenceModel? _inference;
  InferenceChat? _chat;
  bool _busy = false;
  Object? _loadError;

  /// The picture waiting to go with the next message, if any.
  Uint8List? _image;

  /// The clip waiting to go with the next message, already WAV-wrapped.
  Uint8List? _audio;

  /// A one-line problem that is not worth losing the chat over — a picture
  /// that would not decode, a microphone permission the user declined.
  String? _notice;

  // Recording state. The samples arrive on a stream, so they are collected
  // here rather than written to a file.
  final _pcm = BytesBuilder();
  StreamSubscription<Uint8List>? _samples;
  Completer<void>? _samplesDone;
  Timer? _clipTimer;
  bool _recording = false;

  /// Asked once, of both sides, and then used everywhere: to open the right
  /// kind of session, to enable each button, and to say why not.
  late final Capability _imageCapability = imageCapability(widget.model);
  late final Capability _audioCapability = audioCapability(widget.model);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // maxTokens is the CONTEXT WINDOW — prompt + history + reply share it.
      // Both modalities spend it: the vision encoder turns one picture into
      // hundreds of tokens and the audio encoder turns every second of sound
      // into more. This is why a multimodal chat asks for a bigger window
      // than a text one, not because the replies got longer.
      final inference = await FlutterGemma.getActiveModel(maxTokens: 4096);
      // Hold the runtime before opening a chat on it: `createChat` can throw,
      // and a model this page never stored is a model `dispose` can never
      // close. A page that is already gone holds nothing, so it closes it here.
      if (!mounted) {
        await inference.close();
        return;
      }
      setState(() => _inference = inference);

      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // BOTH halves of each question, in one expression. These map to
        // `enableVisionModality` and `enableAudioModality` on the native
        // session: asking for a modality the weights do not have fails at
        // session creation, and asking for one the platform cannot carry
        // opens a session nothing will ever feed.
        supportImage: _imageCapability.available,
        supportAudio: _audioCapability.available,
        maxOutputTokens: 256,
      );
      if (!mounted) return;
      setState(() => _chat = chat);
    } catch (error) {
      // Loading is the likeliest thing to fail on a real device: a forgotten
      // engine package, too little memory, a half-written model file. Show it
      // instead of sitting on the progress bar forever.
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _retryLoad() {
    setState(() => _loadError = null);
    _load();
  }

  /// Reads a picture into memory. The plugin takes bytes, not a path — which
  /// is why this works the same on a phone and in a desktop file dialog.
  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        // The vision encoder resizes to its own input square anyway, so a
        // 12-megapixel original costs decode time and memory for nothing.
        maxWidth: 1024,
        maxHeight: 1024,
      );
      // Null means the user closed the picker. That is not an error, and
      // reporting it as one is how an app earns a reputation for shouting.
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _image = bytes;
          // One attachment at a time: the turn reads as a question about the
          // thing attached, and two things make it a question about neither.
          _audio = null;
          _notice = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Could not read that image: $error');
      }
    }
  }

  /// Starts capture, collecting raw samples in memory.
  ///
  /// This is the third question, and it is not the model's or the platform's:
  /// it is the device's. `hasPermission()` is the only honest way to ask it —
  /// on an iOS Simulator with no input device, or after the user has said no
  /// once, the answer is false however capable the model and the OS are.
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(
            () => _notice =
                'No microphone. Grant the permission, or run on a device that '
                'has one — this is the device saying no, not the model.',
          );
        }
        return;
      }

      _pcm.clear();
      final done = Completer<void>();
      final stream = await _recorder.startStream(
        const RecordConfig(
          // Raw PCM, not a container: `startStream` hands the samples to Dart
          // instead of writing a file, so nothing here needs a writable path.
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channels,
        ),
      );
      _samplesDone = done;
      _samples = stream.listen(
        _pcm.add,
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
      );
      _clipTimer = Timer(_maxClip, _stopRecording);
      if (mounted) {
        setState(() {
          _recording = true;
          _image = null;
          _notice = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _notice = 'Could not start recording: $error';
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    _clipTimer?.cancel();
    _clipTimer = null;
    try {
      await _recorder.stop();
      // `stop()` returns before the platform has flushed its last buffers.
      // The stream's done event is what says every sample arrived; the
      // timeout is there so a platform that never closes it cannot hang the
      // button, at the cost of the final fraction of a second.
      await _samplesDone?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _samples?.cancel();
      final pcm = _pcm.takeBytes();
      if (mounted) {
        setState(() {
          _recording = false;
          _audio = pcm.isEmpty
              ? null
              : wavFromPcm16(pcm, sampleRate: _sampleRate, channels: _channels);
          if (pcm.isEmpty) _notice = 'The recording came back empty.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _notice = 'Could not finish the recording: $error';
        });
      }
    } finally {
      _samples = null;
      _samplesDone = null;
    }
  }

  Future<void> _send() async {
    final chat = _chat;
    final text = _input.text.trim();
    final image = _image;
    final audio = _audio;
    // An attachment on its own is a valid turn — "what is this?" is implied.
    if (chat == null ||
        _busy ||
        (text.isEmpty && image == null && audio == null)) {
      return;
    }

    setState(() {
      _turns
        ..add(
          _Turn(text, fromUser: true, image: image, hasAudio: audio != null),
        )
        // The reply starts empty and grows as chunks arrive.
        ..add(const _Turn('', fromUser: false));
      _input.clear();
      _image = null;
      _audio = null;
      _notice = null;
      _busy = true;
    });

    try {
      await chat.addQueryChunk(_message(text, image: image, audio: audio));

      final buffer = StringBuffer();
      await for (final chunk in chat.generateChatResponseAsync()) {
        // Each TextResponse carries only the NEW text, not the whole reply
        // so far — append, never replace.
        if (chunk is TextResponse) {
          buffer.write(chunk.token);
          if (!mounted) return;
          setState(
            () => _turns[_turns.length - 1] = _Turn(
              buffer.toString(),
              fromUser: false,
            ),
          );
        }
      }
    } catch (error) {
      // The half-written reply becomes the error, so the empty bubble never
      // just sits there. The chat's own history now holds a user turn the model
      // never answered; a production app would reset it with `clearHistory`.
      if (mounted) {
        setState(
          () => _turns[_turns.length - 1] = _Turn('⚠️ $error', fromUser: false),
        );
      }
    } finally {
      // `_busy` is what disables the composer, so clearing it belongs in
      // `finally` — a failed generation must not lock the app.
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One factory per shape of turn. `Message.withImages` takes a LIST, because
  /// a model that can see one picture can usually see several;
  /// `Message.withAudio` takes exactly one clip; `Message.text` is the same
  /// call with nothing attached.
  Message _message(String text, {Uint8List? image, Uint8List? audio}) {
    if (image != null) {
      return Message.withImages(text: text, imageBytes: [image], isUser: true);
    }
    if (audio != null) {
      return Message.withAudio(text: text, audioBytes: audio, isUser: true);
    }
    return Message.text(text: text, isUser: true);
  }

  Future<void> _onAction(_Action action) async {
    try {
      switch (action) {
        case _Switch(:final model):
          await _switchTo(model);
        case _Remove():
          await _removeModel();
      }
    } catch (error) {
      // Closing a runtime and deleting a file can both fail. Surface it the
      // way a failed load is surfaced, and drop the chat with it: a `close()`
      // that threw leaves `_chat` non-null, and "The model did not load." over
      // an enabled composer is a lie.
      if (mounted) {
        setState(() {
          _chat = null;
          _loadError = error;
        });
      }
    }
  }

  /// Release this model's runtime before the app activates another one. Each
  /// holds native memory, and a 2.59 GB model held open while a second one
  /// loads is how a phone runs out of it.
  Future<void> _switchTo(ModelChoice next) async {
    await _inference?.close();
    // Inside `setState`: dropping the chat has to repaint, or the screen keeps
    // showing an enabled composer over a runtime that is gone.
    if (mounted) {
      setState(() {
        _inference = null;
        _chat = null;
      });
      widget.onSwitch(next);
    }
  }

  /// Frees the disk. Close the runtime first — the file is mapped while a
  /// model is open, and deleting it underneath the engine is a crash waiting
  /// to happen.
  Future<void> _removeModel() async {
    await _inference?.close();
    if (mounted) {
      setState(() {
        _inference = null;
        _chat = null;
      });
    }
    await FlutterGemma.uninstallModel(widget.model.fileName);
    if (mounted) widget.onModelRemoved();
  }

  void _showCapabilities() {
    showDialog<void>(
      context: context,
      builder: (context) => _CapabilitySheet(
        model: widget.model,
        image: _imageCapability,
        audio: _audioCapability,
      ),
    );
  }

  @override
  void dispose() {
    // Sessions and models hold native memory — always close them. `dispose`
    // cannot await, so the futures are dropped on purpose, and caught so a
    // failing native teardown does not escape as an unhandled async error.
    _clipTimer?.cancel();
    _samples?.cancel();
    // The recorder holds a microphone the OS will not give to anyone else
    // until it is released.
    _recorder.dispose().catchError((Object _) {});
    _inference?.close().catchError((Object _) {});
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _chat != null;
    final error = _loadError;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.model.label),
        // What this run can and cannot do, on one line, always visible.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'image ${_imageCapability.available ? 'on' : 'off'} · '
              'audio ${_audioCapability.available ? 'on' : 'off'}',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'What can this model do here?',
            onPressed: _showCapabilities,
            icon: const Icon(Icons.info_outline),
          ),
          PopupMenuButton<_Action>(
            // Not while the model is still opening: switching or deleting
            // underneath an in-flight `getActiveModel()` is the crash the
            // comment on `_removeModel` warns about.
            enabled: !_busy && !_recording && (ready || error != null),
            onSelected: _onAction,
            itemBuilder: (context) => [
              for (final m in Models.all)
                if (m.fileName != widget.model.fileName)
                  PopupMenuItem(
                    value: _Switch(m),
                    child: Text('Use ${m.label} (${m.sizeLabel})'),
                  ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _Remove(),
                child: Text('Forget this model'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (error != null)
            _LoadFailed(error: error, onRetry: _retryLoad)
          else if (!ready)
            const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _turns.length,
              itemBuilder: (context, i) => _Bubble(turn: _turns[i]),
            ),
          ),
          if (_image case final image?)
            _Attachment(
              preview: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  image,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              label: 'Image attached to the next message',
              onClear: () => setState(() => _image = null),
            ),
          if (_audio case final audio?)
            _Attachment(
              preview: const Icon(Icons.graphic_eq, size: 40),
              label:
                  'Recording attached — ${(audio.lengthInBytes - 44) ~/ (_sampleRate * 2)}s',
              onClear: () => setState(() => _audio = null),
            ),
          if (_notice case final notice?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          // Say it, do not just grey it out. A disabled button teaches the
          // user that the app is broken; a sentence naming the side that
          // refused teaches them whether to change the model or the device.
          _BlockedLine(what: 'Image input', capability: _imageCapability),
          _BlockedLine(what: 'Audio input', capability: _audioCapability),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip:
                        _imageCapability.blockedBecause ?? 'Attach an image',
                    onPressed:
                        _imageCapability.available &&
                            ready &&
                            !_busy &&
                            !_recording
                        ? _pickImage
                        : null,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: _audioCapability.blockedBecause ?? 'Record a clip',
                    onPressed: _audioCapability.available && ready && !_busy
                        ? (_recording ? _stopRecording : _startRecording)
                        : null,
                    color: _recording ? theme.colorScheme.error : null,
                    icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: ready && !_busy,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Recording… tap stop'
                            : ready
                            ? 'Ask something'
                            : error != null
                            ? 'No model loaded'
                            : 'Loading the model…',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: ready && !_busy && !_recording ? _send : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two questions, asked out loud, for both modalities at once.
///
/// This is the screen the codelab exists for: it never says "not supported".
/// It says which of the two independent answers was no, so the user knows
/// whether to change the model or to change the device.
class _CapabilitySheet extends StatelessWidget {
  const _CapabilitySheet({
    required this.model,
    required this.image,
    required this.audio,
  });

  final ModelChoice model;
  final Capability image;
  final Capability audio;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(model.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, 'Image input', image),
          const SizedBox(height: 16),
          _row(context, 'Audio input', audio),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  static Widget _row(BuildContext context, String what, Capability c) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(what, style: theme.textTheme.titleSmall),
        Text('the model: ${c.byModel ? 'yes' : 'no'}'),
        Text('this platform: ${c.byPlatform ? 'yes' : 'no'}'),
        if (c.blockedBecause case final why?)
          Text(
            why,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else
          Text('available', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// One line naming a modality this app cannot use here, and which side of the
/// question refused it. Renders nothing when the modality works.
class _BlockedLine extends StatelessWidget {
  const _BlockedLine({required this.what, required this.capability});

  final String what;
  final Capability capability;

  @override
  Widget build(BuildContext context) {
    final why = capability.blockedBecause;
    if (why == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        '$what is off — $why.',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// The thing queued for the next message, with a way to change your mind.
class _Attachment extends StatelessWidget {
  const _Attachment({
    required this.preview,
    required this.label,
    required this.onClear,
  });

  final Widget preview;
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(width: 56, height: 56, child: Center(child: preview)),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          IconButton(
            tooltip: 'Remove the attachment',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the loading bar when the model could not be opened.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('The model did not load.\n$error', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _Turn {
  const _Turn(
    this.text, {
    required this.fromUser,
    this.image,
    this.hasAudio = false,
  });

  final String text;
  final bool fromUser;

  /// Kept so the transcript shows what the model was actually asked about.
  final Uint8List? image;

  /// A clip has nothing to draw, so the transcript says one was sent rather
  /// than pretending the turn was text-only.
  final bool hasAudio;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: turn.fromUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (turn.image case final image?) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(image, width: 200, fit: BoxFit.cover),
              ),
              if (turn.text.isNotEmpty) const SizedBox(height: 8),
            ],
            if (turn.hasAudio) ...[
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq, size: 16),
                  SizedBox(width: 6),
                  Text('recording'),
                ],
              ),
              if (turn.text.isNotEmpty) const SizedBox(height: 8),
            ],
            if (turn.text.isNotEmpty) SelectableText(turn.text),
          ],
        ),
      ),
    );
  }
}

sealed class _Action {
  const _Action();
}

final class _Switch extends _Action {
  const _Switch(this.model);
  final ModelChoice model;
}

final class _Remove extends _Action {
  const _Remove();
}
