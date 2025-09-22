import 'base_model.dart';

enum EmbeddingModel implements EmbeddingModelInterface {
  // EmbeddingGemma models with correct URLs and sizes
  embeddingGemma1024(
    url: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
    tokenizerUrl: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    filename: 'embeddinggemma-300M_seq1024_mixed-precision.tflite',
    tokenizerFilename: 'sentencepiece.model',
    displayName: 'EmbeddingGemma 1024',
    size: '183MB',
    dimension: 1024,
    needsAuth: true,
  ),

  embeddingGemma2048(
    url: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq2048_mixed-precision.tflite',
    tokenizerUrl: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    filename: 'embeddinggemma-300M_seq2048_mixed-precision.tflite',
    tokenizerFilename: 'sentencepiece.model',
    displayName: 'EmbeddingGemma 2048',
    size: '196MB',
    dimension: 2048,
    needsAuth: false,
  ),

  embeddingGemma256(
    url: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite',
    tokenizerUrl: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    filename: 'embeddinggemma-300M_seq256_mixed-precision.tflite',
    tokenizerFilename: 'sentencepiece.model',
    displayName: 'EmbeddingGemma 256',
    size: '179MB',
    dimension: 256,
    needsAuth: false,
  ),

  embeddingGemma512(
    url: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq512_mixed-precision.tflite',
    tokenizerUrl: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
    filename: 'embeddinggemma-300M_seq512_mixed-precision.tflite',
    tokenizerFilename: 'sentencepiece.model',
    displayName: 'EmbeddingGemma 512',
    size: '179MB',
    dimension: 512,
    needsAuth: false,
  ),

  gecko256(
    url: 'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_256_quant.tflite',
    tokenizerUrl: 'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model',
    filename: 'gecko-256-quant.tflite',
    tokenizerFilename: 'sentencepiece.model',
    displayName: 'Gecko 256',
    size: '114MB',
    dimension: 256,
    needsAuth: false,
  );

  /// Enum fields
  @override
  final String url;
  @override
  final String tokenizerUrl;
  @override
  final String filename;
  @override
  final String tokenizerFilename;
  @override
  final String displayName;
  @override
  final String size;
  @override
  final int dimension;
  final bool needsAuth;

  /// Constructor
  const EmbeddingModel({
    required this.url,
    required this.tokenizerUrl,
    required this.filename,
    required this.tokenizerFilename,
    required this.displayName,
    required this.size,
    required this.dimension,
    required this.needsAuth,
  });

  // BaseModel interface implementation
  @override
  String get name => toString().split('.').last;
  
  @override
  bool get isEmbeddingModel => true;

  @override
  String? get licenseUrl => null; // Most embedding models don't have specific license URLs
}