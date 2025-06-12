import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';

enum Model {
  gemma3GpuLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    url: 'assets/gemma3-1b-it-int4.task',
    filename: 'gemma3-1b-it-int4.task',
    displayName: 'Gemma3 1B IT (GPU / Local)',
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
    url: 'assets/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3 Nano E2B IT Multimodal (Local Asset) ',
    licenseUrl: '',
    needsAuth: false,
    localModel: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 5,
    topP: 0.95,
  ),


  deepseek(
    url:
    'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/deepseek_q8_ekv1280.task',
    filename: 'deepseek_q8_ekv1280.task',
    displayName: 'DeepSeek Q8 EKV1280 (CPU) 1.7Gb',
    licenseUrl: '',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.deepSeek,
    temperature: 0.6,
    topK: 40,
    topP: 0.7,
  ),

  // Models from JSON - Gemma 3n E2B (Updated version)
  gemma3nGpu_2B(
    url:
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3n E2B IT Multimodal (GPU) 3.1Gb',
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
  ),
  gemma3nCpu_2B(
    url:
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3n E2B IT Multimodal (CPU) 3.1Gb',
    licenseUrl: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
  ),

  gemma3nGpu_4B(
    url:
    'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    filename: 'gemma-3n-E4B-it-int4.task',
    displayName: 'Gemma 3n E4B IT Multimodal (GPU) 6.5Gb',
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
  ),
  gemma3nCpu_4B(
    url:
    'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    filename: 'gemma-3n-E4B-it-int4.task',
    displayName: 'Gemma 3n E4B IT Multimodal (CPU) 6.5Gb',
    licenseUrl: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
  ),

  // Models from JSON - Gemma3 1B IT q4 (Updated version)
  gemma3Gpu_1B(
    url:
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    filename: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    displayName: 'Gemma3 1B IT q4 (GPU) 0.5Gb',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
  ),
  gemma3Cpu_1B(
    url:
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    filename: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    displayName: 'Gemma3 1B IT q4 (CPU) 0.5Gb',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.gemmaIt,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
  ),

  // Models from JSON - Qwen2.5 1.5B Instruct q8
  qwen25_1_5B_InstructCpu(
    url:
    'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    filename: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    displayName: 'Qwen2.5 1.5B Instruct q8 (CPU) 1.6Gb',
    licenseUrl: 'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.general,
    temperature: 1.0,
    topK: 40,
    topP: 0.95,
    maxTokens: 1024,
  );

  // Define fields for the enum
  final String url;
  final String filename;
  final String displayName;
  final String licenseUrl;
  final bool needsAuth;
  final bool localModel;
  final PreferredBackend preferredBackend;
  final ModelType modelType;
  final double temperature;
  final int topK;
  final double topP;
  final bool supportImage;
  final int maxTokens;
  final int? maxNumImages;

  // Constructor for the enum
  const Model({
    required this.url,
    required this.filename,
    required this.displayName,
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
  });
}