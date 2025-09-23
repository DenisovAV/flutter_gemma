enum ModelType {
  general,
  gemmaIt,
  deepSeek,
  qwen,
  llama,
  hammer,
}

enum ModelFileType {
  task,        // .task files - MediaPipe handles templates internally
  binary,      // .bin, .tflite files - need manual template formatting
}
