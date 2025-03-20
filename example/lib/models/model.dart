import 'package:flutter_gemma/pigeon.g.dart';

enum Model {
  gemma3Gpu(
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.gpu,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),
  gemma3Cpu(
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    licenseUrl: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
    needsAuth: true,
    preferredBackend: PreferredBackend.cpu,
    temperature: 0.1,
    topK: 64,
    topP: 0.95,
  ),

  deepseek(
    url:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/deepseek_q8_ekv1280.task',
    licenseUrl: '',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    temperature: 0.6,
    topK: 40,
    topP: 0.7,
  );

  // Define fields for the enum
  final String url;
  final String licenseUrl;
  final bool needsAuth;
  final PreferredBackend preferredBackend;
  final double temperature;
  final int topK;
  final double topP;

  // Constructor for the enum
  const Model({
    required this.url,
    required this.licenseUrl,
    required this.needsAuth,
    required this.preferredBackend,
    required this.temperature,
    required this.topK,
    required this.topP,
  });
}
