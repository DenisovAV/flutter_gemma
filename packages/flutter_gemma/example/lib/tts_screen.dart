import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/models/tts_model.dart';
import 'package:flutter_gemma_example/utils/audio_converter.dart';
import 'package:flutter_gemma_example/utils/platform_io_helper.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// TTS synthesize screen — mirrors [SttScreen]'s install-in-initState /
/// `mounted`-after-await / reentrancy discipline, but the flow is simpler:
/// no recording, just a text field → synthesize → play. Installs
/// (idempotent) and activates [TtsModel.matcha] — the only catalog entry
/// with a shipped `TtsModelProfile` today (see `models/tts_model.dart`) —
/// then lets the user type text and hear it spoken via
/// [SpeechSynthesizer.synthesize] + `just_audio` playback of the
/// WAV-wrapped PCM (`AudioConverter.pcmToWav`).
///
/// `createFile` (not raw `dart:io`) is used to write the WAV to a temp file
/// so this screen still compiles for web, where `flutter_gemma_speech` has
/// no TTS arm (the init call surfaces that as [_initError] instead).
class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  static const _model = TtsModel.matcha;

  SpeechSynthesizer? _synth;
  bool _isInitializing = true;
  String? _initError;
  int? _downloadPercent;

  final _textController = TextEditingController(text: 'Hello world.');
  final _player = AudioPlayer();

  bool _isSpeaking = false;
  String? _speakError;

  @override
  void initState() {
    super.initState();
    _initializeTtsModel();
  }

  @override
  void dispose() {
    _textController.dispose();
    _player.dispose();
    _synth?.close();
    super.dispose();
  }

  /// Install (idempotent) + activate [_model], then create the
  /// [SpeechSynthesizer]. Mirrors `SttScreen._initializeSttModel`.
  Future<void> _initializeTtsModel() async {
    try {
      await FlutterGemma.installTts()
          .fromNetwork(_model.baseUrl)
          .ofType(_model.ttsModelType)
          .withProgress((percent) {
            if (!mounted) return;
            setState(() => _downloadPercent = percent);
          })
          .install();

      final synth = await FlutterGemma.getActiveTts();

      if (!mounted) return;
      setState(() {
        _synth = synth;
        _isInitializing = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TtsScreen] Could not initialize TTS model: $e');
      }
      if (!mounted) return;
      setState(() {
        _initError = e.toString();
        _isInitializing = false;
      });
    }
  }

  Future<void> _speak() async {
    if (_synth == null || _isSpeaking) return; // reentrancy guard
    setState(() {
      _isSpeaking = true;
      _speakError = null;
    });
    try {
      final pcm = await _synth!.synthesize(_textController.text);
      if (!mounted) return;

      final wav = AudioConverter.pcmToWav(pcm, sampleRate: _synth!.sampleRate);
      final tempDir = await getTemporaryDirectory();
      if (!mounted) return;

      final file = createFile('${tempDir.path}/tts_output.wav');
      await file.writeAsBytes(wav);
      if (!mounted) return;

      await _player.setFilePath(file.path);
      await _player.play();

      if (!mounted) return;
      setState(() => _isSpeaking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speakError = e.toString();
        _isSpeaking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b2351),
      appBar: AppBar(
        title: Text(_model.displayName),
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
            if (!_isInitializing && _initError == null) _buildSpeakSection(),
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
              'Model Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Size:', _model.size),
            _buildInfoRow('Type:', 'Text-to-Speech'),
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
                  ? 'Downloading model… $percent%'
                  : 'Installing model and preparing synthesizer…',
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
              'Failed to prepare the TTS model',
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

  Widget _buildSpeakSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Synthesize',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _textController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Text to speak',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1a3a5c),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSpeaking ? null : _speak,
            icon: Icon(_isSpeaking ? Icons.volume_up : Icons.play_arrow),
            label: Text(_isSpeaking ? 'Speaking…' : 'Speak'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2a5a8c),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_speakError != null) ...[
          const SizedBox(height: 16),
          Text(
            _speakError!,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
