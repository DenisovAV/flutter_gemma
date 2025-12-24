enum ModelType {
  general,
  gemmaIt,
  deepSeek,
  qwen,
  llama,
  hammer,
  functionGemma,
}

enum ModelFileType {
  task, // .task and .litertlm files - MediaPipe handles chat templates internally
  binary, // .bin and .tflite files - require manual chat template formatting
}
