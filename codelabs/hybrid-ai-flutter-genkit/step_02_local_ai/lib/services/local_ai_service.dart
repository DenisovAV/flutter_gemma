import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_flutter_gemma/genkit_flutter_gemma.dart';

import 'ai_service.dart';

// The on-device LLM installs straight from Hugging Face by repo + file.
const String _hfRepo = 'litert-community/Gemma3-1B-IT';
const String _hfModelFile =
    'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';
const String _embeddingModelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
const String _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

// Pass at build time: flutter run --dart-define=HF_TOKEN=hf_xxx
const String _hfToken = String.fromEnvironment('HF_TOKEN');

const String _modelName = 'gemma-3-1b-it';
const String _embedderName = 'embedding-gemma-300m';

class LocalAIService implements AIService {
  Genkit? _ai;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // Shared Genkit instance exposed for RagService to use for embeddings.
  Genkit get ai {
    final ai = _ai;
    if (ai == null) throw StateError('LocalAIService not initialized');
    return ai;
  }

  String get embedderName => _embedderName;

  @override
  Future<void> initialize({void Function(int)? onProgress}) async {
    if (_isInitialized) return;

    // flutter_gemma 1.x registers no engine by default — opt into LiteRT-LM.
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

    // Download the .litertlm model (skipped if already installed).
    await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
        )
        .fromHuggingFace(
          _hfRepo,
          file: _hfModelFile,
          token: _hfToken.isEmpty ? null : _hfToken,
        )
        .withProgress((p) => onProgress?.call(p)) // p is int 0..100
        .install();

    await FlutterGemma.installEmbedder()
        .modelFromNetwork(
          _embeddingModelUrl,
          token: _hfToken.isNotEmpty ? _hfToken : null,
        )
        .tokenizerFromNetwork(
          _tokenizerUrl,
          token: _hfToken.isNotEmpty ? _hfToken : null,
        )
        .install();

    // One Genkit instance for both inference and embeddings.
    _ai = Genkit(
      plugins: [
        GenkitFlutterGemmaPlugin(
          models: [
            FlutterGemmaModelConfig(
              name: _modelName,
              modelType: ModelType.gemmaIt,
              fileType: ModelFileType.litertlm,
            ),
          ],
          embedders: [FlutterGemmaEmbedderConfig(name: _embedderName)],
        ),
      ],
    );

    _isInitialized = true;
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    final stream = ai.generateStream(
      model: flutterGemma.model(_modelName),
      prompt: prompt,
    );

    await for (final chunk in stream) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Future<void> dispose() async {
    _ai = null;
    _isInitialized = false;
  }
}
