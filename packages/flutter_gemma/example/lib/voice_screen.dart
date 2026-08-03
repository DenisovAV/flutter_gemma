import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/models/model.dart';
import 'package:flutter_gemma_example/models/stt_model.dart';
import 'package:flutter_gemma_example/models/tts_model.dart';
import 'package:flutter_gemma_example/services/auth_token_service.dart';
import 'package:flutter_gemma_example/utils/audio_converter.dart';
import 'package:flutter_gemma_example/utils/platform_io_helper.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Voice loop reference screen — push-to-talk STT -> LLM -> TTS driven by
/// [VoiceSession]. Mirrors `SttScreen` for capture (AudioRecorder + 5-second
/// timer + WAV parse) and `TtsScreen` for playback (AudioConverter.pcmToWav +
/// just_audio), and wires both through one [VoiceSession.fromChat] built
/// from three fixed models: [SttModel.moonshineTiny] (the only STT catalog
/// entry with a shipped profile today), [_llmModel] (a small text-only chat
/// model, no tools — `VoiceSession.fromChat` requires `chat.tools.isEmpty`),
/// and [TtsModel.matcha] (the only TTS catalog entry with a shipped profile).
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  static const _sttModel = SttModel.moonshineTiny;
  static const _llmModel = Model.gemma3_1B;
  static const _ttsModel = TtsModel.matcha;

  SpeechRecognizer? _recognizer;
  SpeechSynthesizer? _synth;
  InferenceChat? _chat;
  VoiceSession? _session;

  bool _isInitializing = true;
  String? _initError;
  String _stage = 'Downloading speech model';
  int? _downloadPercent;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final _player = AudioPlayer();

  bool _isRecording = false;
  // Reentrancy guards for the async gap BEFORE _isRecording/_turnRunning flip
  // true (a rapid double-tap during permission/IO would otherwise start two
  // overlapping operations). Not UI state — plain guards.
  bool _startingRecording = false;
  bool _startingBundledClip = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  static const _maxRecordingDuration = Duration(seconds: 5);

  bool _turnRunning = false;
  String? _transcript;
  String _replyText = '';
  String? _turnError;

  @override
  void initState() {
    super.initState();
    _initializeVoiceSession();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _player.dispose();
    _recognizer?.close();
    _synth?.close();
    _chat?.close();
    super.dispose();
  }

  /// Install (idempotent) + activate STT, TTS and the LLM chat, then build
  /// the [VoiceSession]. Mirrors `SttScreen._initializeSttModel` /
  /// `TtsScreen._initializeTtsModel`.
  Future<void> _initializeVoiceSession() async {
    try {
      // --- STT ---
      final sttToken = _sttModel.needsAuth
          ? await AuthTokenService.loadToken()
          : null;
      if (!mounted) return;
      setState(() {
        _stage = 'Downloading speech model';
        _downloadPercent = null;
      });
      await FlutterGemma.installStt()
          .modelFromNetwork(_sttModel.modelUrl, token: sttToken)
          .tokenizerFromNetwork(_sttModel.tokenizerUrl, token: sttToken)
          .ofType(_sttModel.sttModelType)
          .withModelProgress((percent) {
            if (!mounted) return;
            setState(() => _downloadPercent = percent);
          })
          .withTokenizerProgress((percent) {
            if (!mounted) return;
            setState(() => _downloadPercent = percent);
          })
          .install();
      final recognizer = await FlutterGemma.getActiveStt();

      // --- TTS ---
      if (!mounted) return;
      setState(() {
        _stage = 'Downloading voice model';
        _downloadPercent = null;
      });
      await FlutterGemma.installTts()
          .fromNetwork(_ttsModel.baseUrl)
          .ofType(_ttsModel.ttsModelType)
          .withProgress((percent) {
            if (!mounted) return;
            setState(() => _downloadPercent = percent);
          })
          .install();
      final synth = await FlutterGemma.getActiveTts();

      // --- LLM (no tools — see class doc) ---
      String? llmToken;
      if (_llmModel.needsAuth) {
        llmToken = await AuthTokenService.loadToken();
      }
      if (!mounted) return;
      setState(() {
        _stage = 'Downloading language model';
        _downloadPercent = null;
      });
      await FlutterGemma.installModel(
        modelType: _llmModel.modelType,
        fileType: _llmModel.fileType,
      ).fromNetwork(_llmModel.url, token: llmToken).withProgress((percent) {
        if (!mounted) return;
        setState(() => _downloadPercent = percent);
      }).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: _llmModel.maxTokens,
        preferredBackend: _llmModel.preferredBackend,
      );
      final chat = await model.createChat(
        temperature: _llmModel.temperature,
        randomSeed: 1,
        topK: _llmModel.topK,
        topP: _llmModel.topP,
        tokenBuffer: 256,
        tools: const [],
        modelType: _llmModel.modelType,
        maxOutputTokens: 128,
        systemInstruction:
            'Reply concisely in one or two short sentences; your reply will '
            'be spoken aloud.',
      );

      final session = VoiceSession.fromChat(
        recognizer: recognizer,
        chat: chat,
        synthesizer: synth,
      );

      if (!mounted) return;
      setState(() {
        _recognizer = recognizer;
        _synth = synth;
        _chat = chat;
        _session = session;
        _isInitializing = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VoiceScreen] Could not initialize voice session: $e');
      }
      if (!mounted) return;
      setState(() {
        _initError = e.toString();
        _isInitializing = false;
      });
    }
  }

  Future<void> _runTurn(Uint8List pcm16kMono) async {
    final session = _session;
    if (session == null || _turnRunning) return; // reentrancy guard
    setState(() {
      _turnRunning = true;
      _transcript = null;
      _replyText = '';
      _turnError = null;
    });
    try {
      await for (final event in session.runTurn(pcm16kMono)) {
        switch (event) {
          case VoiceTranscriptEvent(:final text):
            if (!mounted) return;
            setState(() => _transcript = text);
            break;
          case VoiceReplyTextEvent(:final chunk):
            if (!mounted) return;
            setState(() => _replyText += chunk);
            break;
          case VoiceReplyAudioEvent(:final pcm, :final sampleRate):
            await _playReply(pcm, sampleRate);
            break;
          case VoiceTurnInterruptedEvent():
            await _player.stop();
            break;
          case VoiceTurnCompleteEvent():
          case VoiceErrorEvent():
            break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _turnError = e.toString());
    } finally {
      if (mounted) setState(() => _turnRunning = false);
    }
  }

  /// WAV-wrap the synthesized reply PCM and play it via just_audio. Mirrors
  /// `TtsScreen._speak`'s playback tail (temp file -> setFilePath -> play).
  Future<void> _playReply(Uint8List pcm, int sampleRate) async {
    final wav = AudioConverter.pcmToWav(pcm, sampleRate: sampleRate);
    final dir = await getTemporaryDirectory();
    if (!mounted) return;
    final file = createFile('${dir.path}/voice_reply.wav');
    await file.writeAsBytes(wav);
    if (!mounted) return;
    await _player.setFilePath(file.path);
    await _player.play();
  }

  /// Barge-in: stop the in-flight turn (the player is also stopped by the
  /// resulting [VoiceTurnInterruptedEvent] handled in [_runTurn], for the
  /// mid-generation case). `interrupt()` is a documented no-op once the reply
  /// has already reached playback (v1 emits its one final audio event +
  /// Complete before playback finishes), so stop the player explicitly here
  /// too — that's what actually cuts the audio during that case. Idempotent
  /// — a no-op when no turn is running.
  Future<void> _bargeIn() async {
    await _session?.interrupt();
    await _player.stop();
  }

  Future<void> _runBundledClip() async {
    if (_turnRunning || _startingBundledClip) return; // guard the load gap
    _startingBundledClip = true;
    try {
      final data = await rootBundle.load('assets/test/test_audio.wav');
      final wavBytes = data.buffer.asUint8List();
      final parsed = AudioConverter.parseWav(wavBytes);
      final pcm = AudioConverter.toPCM16kHzMono(
        parsed.pcmData,
        sourceSampleRate: parsed.sampleRate,
        sourceChannels: parsed.channels,
      );
      await _runTurn(pcm);
    } catch (e) {
      if (!mounted) return;
      setState(() => _turnError = e.toString());
    } finally {
      _startingBundledClip = false;
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecordingAndRunTurn();
    } else {
      if (_startingRecording) return; // guard the start-up async gap
      _startingRecording = true;
      try {
        await _startRecording();
      } finally {
        _startingRecording = false;
      }
    }
  }

  Future<void> _startRecording() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!kIsWeb && (platformIsAndroid || platformIsIOS)) {
      final status = await Permission.microphone.request();
      if (!mounted)
        return; // a permission dialog is a classic navigate-away gap
      if (!status.isGranted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required for recording'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!await _audioRecorder.hasPermission()) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Microphone not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: kIsWeb ? '' : '$systemTempPath/voice_recording.wav',
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
        _transcript = null;
        _replyText = '';
        _turnError = null;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
        if (_recordingDuration >= _maxRecordingDuration) {
          _stopRecordingAndRunTurn();
        }
      });
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
    }
  }

  Future<void> _stopRecordingAndRunTurn() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path == null) return;

      Uint8List wavBytes;
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        wavBytes = response.bodyBytes;
      } else {
        final file = createFile(path);
        wavBytes = await file.readAsBytes();
        await file.delete();
      }

      final parsed = AudioConverter.parseWav(wavBytes);
      final pcm = AudioConverter.toPCM16kHzMono(
        parsed.pcmData,
        sourceSampleRate: parsed.sampleRate,
        sourceChannels: parsed.channels,
      );
      await _runTurn(pcm);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to save recording: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b2351),
      appBar: AppBar(
        title: const Text('Voice Loop'),
        backgroundColor: const Color(0xFF0b2351),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModelInfoCard(),
            const SizedBox(height: 24),
            if (_isInitializing) _buildInitializingState(),
            if (!_isInitializing && _initError != null) _buildInitError(),
            if (!_isInitializing && _initError == null) ...[
              _buildActions(),
              const SizedBox(height: 24),
              _buildResults(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelInfoCard() {
    return Card(
      color: const Color(0xFF1a3a5c),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Voice Loop (STT -> LLM -> TTS)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('STT:', _sttModel.displayName),
            _buildInfoRow('LLM:', _llmModel.displayName),
            _buildInfoRow('TTS:', _ttsModel.displayName),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitializingState() {
    final percent = _downloadPercent;
    final showPercent = percent != null && percent < 100;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          children: [
            CircularProgressIndicator(
              color: Colors.blue,
              value: showPercent ? percent / 100.0 : null,
            ),
            const SizedBox(height: 16),
            Text(
              showPercent
                  ? '$_stage… $percent%'
                  : 'Installing models and preparing the voice session…',
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitError() {
    return Card(
      color: const Color(0xFF1a3a5c),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Failed to prepare the voice session',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _initError!,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Talk',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (_turnRunning || _isRecording)
                    ? null
                    : _runBundledClip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a4a7c),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Run Bundled Clip'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _turnRunning ? null : _toggleRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                label: Text(
                  _isRecording
                      ? 'Stop (${_recordingDuration.inSeconds}s)'
                      : 'Record & Run Turn',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording
                      ? Colors.red
                      : const Color(0xFF2a5a8c),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _turnRunning ? _bargeIn : null,
            icon: const Icon(Icons.front_hand),
            label: const Text('Stop / Barge-in'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Colors.orangeAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    return SizedBox(
      height: 280,
      child: Card(
        color: const Color(0xFF1a3a5c),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turn Log',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildResultsContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsContent() {
    if (_turnError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _turnError!,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_transcript == null && _replyText.isEmpty && !_turnRunning) {
      return const Center(
        child: Text(
          'Run the bundled clip or record your own to hear a reply.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_turnRunning) ...[
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue,
                  ),
                ),
                SizedBox(width: 12),
                Text('Running turn…', style: TextStyle(color: Colors.white60)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_transcript != null) ...[
            const Text(
              'You said:',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              _transcript!.isEmpty ? '(empty transcript)' : _transcript!,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
          ],
          if (_replyText.isNotEmpty) ...[
            const Text(
              'Reply:',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              _replyText,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }
}
