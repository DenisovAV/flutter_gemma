// ignore_for_file: unused_element_parameter

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'base_model.dart';

// Platform detection that's safe for web
bool get _isDesktop {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

enum Model implements InferenceModelInterface {
  // === GEMMA MODELS (Top Priority) ===

  // Gemma 3 Nano models (Multimodal + Function Calls)
  gemma3n_2B(
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    webUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4-Web.litertlm',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3 Nano E2B IT',
    size: '3.1GB',
    licenseUrl: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    supportAudio: false, // E2B does NOT have TF_LITE_AUDIO_ENCODER - only vision
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: false, // Disabled - causes issues with multimodal
    foregroundDownload: true, // Large model - use foreground service on Android
  ),
  gemma3n_4B(
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    webUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4-Web.litertlm',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    filename: 'gemma-3n-E4B-it-int4.task',
    displayName: 'Gemma 3 Nano E4B IT',
    size: '6.5GB',
    licenseUrl: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    supportAudio: false, // .task files don't have TF_LITE_AUDIO_ENCODER - need .litertlm
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: false, // Disabled - causes issues with multimodal
    foregroundDownload: true, // Large model - use foreground service on Android
  ),

  // Gemma 3 1B model
  gemma3_1B(
    baseUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    webUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4-web.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    filename: 'gemma3-1b-it-int4.task',
    displayName: 'Gemma 3 1B IT',
    size: '0.5GB',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
  ),

  // Gemma 3 270M (Ultra-compact text-only model)
  gemma3_270M(
    baseUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task',
    webUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8-web.task',
    desktopUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.litertlm',
    filename: 'gemma3-270m-it-q8.task',
    displayName: 'Gemma 3 270M IT',
    size: '0.3GB',
    licenseUrl: 'https://huggingface.co/litert-community/gemma-3-270m-it',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
    supportsFunctionCalls: false,
  ),

  // Local Gemma models (for testing)
  gemma3LocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    baseUrl: 'assets/models/gemma3-1b-it-int4-web.task',
    filename: 'gemma3-1b-it-int4-web.task',
    displayName: 'Gemma 3 1B IT (Local)',
    size: '0.5GB',
    licenseUrl: '',
    needsAuth: false,
    localModel: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
  ),
  gemma3nLocalAsset(
      // model file should be pre-downloaded and placed in the assets folder
      baseUrl: 'assets/gemma-3n-E2B-it-int4.task',
      filename: 'gemma-3n-E2B-it-int4.task',
      displayName: 'Gemma 3 Nano E2B IT (Local)',
      size: '3.1GB',
      licenseUrl: '',
      needsAuth: false,
      localModel: true,
      preferredBackend: PreferredBackend.gpu,
      modelType: ModelType.gemmaIt,
      temperature: 0.1,
      topK: 5,
      topP: 0.95,
      supportsFunctionCalls: true,
      supportImage: true,
      supportAudio: false), // .task files don't have audio encoder
  gemma3nWebLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    baseUrl: 'assets/gemma-3n-E4B-it-int4-Web.litertlm',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3 Nano E4B IT Web (Local)',
    size: '4.27GB',
    licenseUrl: '',
    needsAuth: false,
    localModel: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 5,
    topP: 0.95,
    supportsFunctionCalls: false,
    supportImage: true,
    supportAudio: true,
  ),

  // === OTHER MODELS ===

  // Qwen3 0.6B (LiteRT-LM format for web/desktop)
  qwen3_0_6B(
    baseUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    filename: 'Qwen3-0.6B.litertlm',
    displayName: 'Qwen3 0.6B',
    size: '586MB',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen3-0.6B',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.qwen,
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    maxTokens: 4096,
    supportsFunctionCalls: true,
  ),

  deepseek(
    baseUrl:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/deepseek_q8_ekv1280.task',
    filename: 'deepseek_q8_ekv1280.task',
    displayName: 'DeepSeek R1 Distill Qwen 1.5B',
    size: '1.7GB',
    licenseUrl: '',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.deepSeek,
    temperature: 0.6,
    topK: 40,
    topP: 0.7,
    supportsFunctionCalls: true,
    isThinking: true,
  ),

  // Qwen2.5 1.5B Instruct
  qwen25_1_5B_Instruct(
    baseUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    filename: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    displayName: 'Qwen 2.5 1.5B Instruct',
    size: '1.6GB',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.qwen,
    temperature: 1.0,
    topK: 40,
    topP: 0.95,
    maxTokens: 1024,
    supportsFunctionCalls: true,
  ),

  // Qwen2.5 0.5B Instruct (mobile only - no litertlm)
  qwen25_0_5B_Instruct(
    baseUrl:
        'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    filename: 'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    displayName: 'Qwen 2.5 0.5B Instruct',
    size: '0.5GB',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.qwen,
    temperature: 1.0,
    topK: 40,
    topP: 0.95,
    maxTokens: 1024,
    supportsFunctionCalls: true,
  ),

  // SmolLM 135M Instruct (Ultra-small, mobile only)
  smolLM_135M(
    baseUrl:
        'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    filename: 'SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    displayName: 'SmolLM 135M Instruct',
    size: '135MB',
    licenseUrl: 'https://huggingface.co/litert-community/SmolLM-135M-Instruct',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.general,
    temperature: 0.7,
    topK: 40,
    topP: 0.9,
    maxTokens: 1024,
    supportsFunctionCalls: false,
  ),

  // FastVLM 0.5B (Vision-Language Model, desktop only - litertlm)
  fastVLM_0_5B(
    baseUrl:
        'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
    filename: 'FastVLM-0.5B.litertlm',
    displayName: 'FastVLM 0.5B (Vision)',
    size: '0.5GB',
    licenseUrl: 'https://huggingface.co/litert-community/FastVLM-0.5B',
    needsAuth: false,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.general,
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    maxTokens: 2048,
    supportImage: true,
    maxNumImages: 1,
    supportsFunctionCalls: false,
  ),

  // Phi-4 Mini Instruct
  phi4_mini(
    baseUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.task',
    webUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    filename: 'Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.task',
    displayName: 'Phi-4 Mini Instruct',
    size: '3.9GB',
    licenseUrl: 'https://huggingface.co/litert-community/Phi-4-mini-instruct',
    needsAuth: false,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.general,
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    maxTokens: 4096,
    supportsFunctionCalls: true,
  ),

  // === FUNCTIONGEMMA MODELS ===

  // FunctionGemma 270M IT (Base model converted to .task)
  functionGemma_270M(
    baseUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task',
    desktopUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
    filename: 'functiongemma-270M-it.task',
    displayName: 'FunctionGemma 270M IT',
    size: '284MB',
    licenseUrl: 'https://huggingface.co/google/functiongemma-270m-it',
    needsAuth: false,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.functionGemma,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
    supportsFunctionCalls: true,
  ),

  // FunctionGemma 270M IT (Local asset)
  functionGemma_270M_local(
    baseUrl: 'assets/models/functiongemma-flutter-1.litertlm',
    filename: 'functiongemma-flutter-1.litertlm',
    displayName: 'FunctionGemma 270M IT (Local)',
    size: '284MB',
    licenseUrl: '',
    needsAuth: false,
    localModel: true,

    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.functionGemma,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
    supportsFunctionCalls: true,
  ),

  // FunctionGemma Flutter Demo (Fine-tuned for example app)
  functionGemma_demo(
    baseUrl:
        'https://huggingface.co/sasha-denisov/functiongemma-flutter-gemma-demo/resolve/main/functiongemma-flutter_q8_ekv1024.task',
    filename: 'functiongemma-flutter_q8_ekv1024.task',
    displayName: 'FunctionGemma Demo (Fine-tuned)',
    size: '284MB',
    licenseUrl: 'https://huggingface.co/sasha-denisov/functiongemma-flutter-gemma-demo',
    needsAuth: false,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.functionGemma,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
    supportsFunctionCalls: true,
  );
  // Define fields for the enum
  final String baseUrl;
  final String? webUrl;
  final String? desktopUrl;

  @override
  final String filename;
  @override
  final String displayName;
  @override
  final String size;
  @override
  final String licenseUrl;
  @override
  final bool needsAuth;
  @override
  final bool localModel;
  @override
  final PreferredBackend preferredBackend;
  @override
  final ModelType modelType;
  @override
  final double temperature;
  @override
  final int topK;
  @override
  final double topP;
  @override
  final bool supportImage;
  final bool supportAudio;
  @override
  final int maxTokens;
  @override
  final int? maxNumImages;
  @override
  final bool supportsFunctionCalls;
  final bool isThinking;
  final ModelFileType fileType;
  final bool? foregroundDownload;

  // Getter for url - returns platform-specific URL
  @override
  String get url {
    // Desktop platforms require .litertlm format
    if (_isDesktop && desktopUrl != null && desktopUrl!.isNotEmpty) {
      return desktopUrl!;
    }
    // Web platform may have different URL
    if (kIsWeb && webUrl != null && webUrl!.isNotEmpty) {
      return webUrl!;
    }
    return baseUrl;
  }

  // Check if model supports desktop (has .litertlm URL)
  bool get supportsDesktop =>
      (desktopUrl != null && desktopUrl!.isNotEmpty) ||
      baseUrl.endsWith('.litertlm');

  // Constructor for the enum
  const Model({
    required this.baseUrl,
    this.webUrl,
    this.desktopUrl,
    required this.filename,
    required this.displayName,
    required this.size,
    required this.licenseUrl,
    required this.needsAuth,
    this.localModel = false,
    required this.preferredBackend,
    required this.modelType,
    required this.temperature,
    required this.topK,
    required this.topP,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxTokens = 1024,
    this.maxNumImages,
    this.supportsFunctionCalls = false,
    this.isThinking = false,
    this.fileType = ModelFileType.task,
    this.foregroundDownload,
  });

  // BaseModel interface implementation
  @override
  String get name => toString().split('.').last;

  @override
  bool get isEmbeddingModel => false;

  // InferenceModelInterface implementation
  @override
  bool get supportsThinking => isThinking;

  /// Returns size in MB (parsed from size string like '3.1GB' or '500MB')
  int get sizeInMB {
    final sizeStr = size.toUpperCase();
    final numMatch = RegExp(r'(\d+\.?\d*)').firstMatch(sizeStr);
    if (numMatch == null) return 0;
    final num = double.parse(numMatch.group(1)!);
    if (sizeStr.contains('GB')) return (num * 1024).round();
    if (sizeStr.contains('MB')) return num.round();
    return 0;
  }

  /// Whether to use foreground service on Android (for large downloads >500MB)
  /// - Explicit foregroundDownload field takes priority
  /// - Otherwise auto-detect: >500MB = true, else null (auto)
  bool? get foreground => foregroundDownload ?? (sizeInMB > 500 ? true : null);
}
