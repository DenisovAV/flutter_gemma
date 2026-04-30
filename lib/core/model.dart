enum ModelType {
  general,
  gemmaIt,
  gemma4, // Gemma 4 E2B/E4B with native function calling tokens
  deepSeek,
  qwen,
  qwen3,
  llama,
  hammer,
  functionGemma,
  phi,
}

enum ModelFileType {
  task, // .task files - MediaPipe handles chat templates internally
  binary, // .bin and .tflite files - require manual chat template formatting
  litertlm, // .litertlm files - LiteRT-LM SDK handles templates on Android/Desktop, manual on iOS
}
