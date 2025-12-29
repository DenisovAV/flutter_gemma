import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'base_model.dart';

enum Model implements InferenceModelInterface {
  // === GEMMA MODELS (Top Priority) ===

  // Gemma 3 Nano models (Multimodal + Function Calls)
  gemma3n_2B(
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    webUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4-Web.litertlm',
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
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),
  gemma3n_4B(
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    webUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4-Web.litertlm',
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
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),

  // Gemma 3 1B model
  gemma3_1B(
    baseUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    webUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4-web.task',
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
      supportImage: true),
  gemma3nWebLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    baseUrl: 'assets/gemma-3n-E4B-it-int4-Web.litertlm',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3 Nano E2B IT Web (Local)',
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
  ),

  // === OTHER MODELS ===

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

  // Models from JSON - Qwen2.5 1.5B Instruct q8
  qwen25_1_5B_InstructCpu(
    baseUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
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

  // TinyLlama 1.1B Chat
  tinyLlama_1_1B(
    baseUrl:
        'https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0/resolve/main/TinyLlama-1.1B-Chat-v1.0_multi-prefill-seq_q8_ekv1280.task',
    filename: 'TinyLlama-1.1B-Chat-v1.0_multi-prefill-seq_q8_ekv1280.task',
    displayName: 'TinyLlama 1.1B Chat',
    size: '1.2GB',
    licenseUrl: 'https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.llama,
    temperature: 0.7,
    topK: 40,
    topP: 0.9,
    maxTokens: 1024,
    supportsFunctionCalls: false,
  ),

  // Hammer 2.1 0.5B (Action Model with strong function calling)
  hammer2_1_0_5B(
    baseUrl:
        'https://huggingface.co/litert-community/Hammer2.1-0.5b/resolve/main/hammer2p1_05b_.task',
    filename: 'hammer2p1_05b_.task',
    displayName: 'Hammer 2.1 0.5B Action Model',
    size: '0.5GB',
    licenseUrl: 'https://huggingface.co/litert-community/Hammer2.1-0.5b',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.hammer,
    temperature: 0.3,
    topK: 40,
    topP: 0.8,
    maxTokens: 1024,
    supportsFunctionCalls: true,
  ),

  // Llama 3.2 1B Instruct
  llama32_1B(
    baseUrl:
        'https://huggingface.co/litert-community/Llama-3.2-1B-Instruct/resolve/main/Llama-3.2-1B-Instruct_seq128_q8_ekv1280.tflite',
    filename: 'Llama-3.2-1B-Instruct_seq128_q8_ekv1280.tflite',
    displayName: 'Llama 3.2 1B Instruct',
    size: '1.1GB',
    licenseUrl: 'https://huggingface.co/litert-community/Llama-3.2-1B-Instruct',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.llama,
    temperature: 0.6,
    topK: 40,
    topP: 0.9,
    maxTokens: 1024,
    supportsFunctionCalls: false,
    fileType: ModelFileType.binary,
  ),

  // Phi-4 Mini Instruct
  phi4_mini(
    baseUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.task',
    webUrl:
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
  @override
  final int maxTokens;
  @override
  final int? maxNumImages;
  @override
  final bool supportsFunctionCalls;
  final bool isThinking;
  final ModelFileType fileType;

  // Getter for url - returns webUrl on web platform if available, otherwise baseUrl
  @override
  String get url {
    if (kIsWeb && webUrl != null && webUrl!.isNotEmpty) {
      return webUrl!;
    }
    return baseUrl;
  }

  // Constructor for the enum
  const Model({
    required this.baseUrl,
    this.webUrl,
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
    this.maxTokens = 1024,
    this.maxNumImages,
    this.supportsFunctionCalls = false,
    this.isThinking = false,
    this.fileType = ModelFileType.task,
  });

  // BaseModel interface implementation
  @override
  String get name => toString().split('.').last;

  @override
  bool get isEmbeddingModel => false;

  // InferenceModelInterface implementation
  @override
  bool get supportsThinking => isThinking;
}
