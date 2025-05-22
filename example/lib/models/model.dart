import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';

enum Model {
  gemma3GpuLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    url: 'assets/gemma3-1b-it-int4.task',
    filename: 'gemma3-1b-it-int4.task',
    displayName: 'Gemma3 1B IT (CPU / Local)',
    licenseUrl: '',
    needsAuth: false,
    localModel: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),
  gemma3Gpu(
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    filename: 'gemma3-1b-it-int4.task',
    displayName: 'Gemma3 1B IT (GPU / Remote)',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),
  gemma3Cpu(
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    filename: 'gemma3-1b-it-int4.task',
    displayName: 'Gemma3 1B IT (CPU / Remote)',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),

  gemma3nGpu(
    url:
        'https://huggingface.co/litert-community/gemma-3-nano-1.5b-IT/resolve/main/gemma-3-nano-1.5b-it-int4.task',
    filename: 'gemma-3-nano-1.5b-it-int4.task',
    displayName: 'Gemma 3 Nano 1.5B IT (GPU / Remote)',
    licenseUrl: 'https://huggingface.co/litert-community/gemma-3-nano-1.5b-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),
  gemma3nCpu(
    url:
        'https://huggingface.co/litert-community/gemma-3-nano-1.5b-IT/resolve/main/gemma-3-nano-1.5b-it-int4.task',
    filename: 'gemma-3-nano-1.5b-it-int4.task',
    displayName: 'Gemma 3 Nano 1.5B IT (CPU / Remote)',
    licenseUrl: 'https://huggingface.co/litert-community/gemma-3-nano-1.5b-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),
  gemma3nLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    url: 'assets/gemma-3-nano-1.5b-it-int4.task',
    filename: 'gemma-3-nano-1.5b-it-int4.task',
    displayName: 'Gemma 3 Nano 1.5B IT (Local Asset)',
    licenseUrl: '',
    needsAuth: false,
    localModel: true,
    preferredBackend: PreferredBackend.gpu,
    modelType: ModelType.gemmaIt,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),

  deepseek(
    url:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/deepseek_q8_ekv1280.task',
    filename: 'deepseek_q8_ekv1280.task',
    displayName: 'DeepSeek Q8 EKV1280 (CPU / Remote)',
    licenseUrl: '',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    modelType: ModelType.deepSeek,
    temperature: 0.6,
    topK: 40,
    topP: 0.7,
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
  });
}
