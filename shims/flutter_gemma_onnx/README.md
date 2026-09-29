# flutter_gemma_onnx

**`flutter_gemma_onnx` is now [`flutter_edge_ai_onnx`](https://pub.dev/packages/flutter_edge_ai_onnx).**

This last release only re-exports `flutter_edge_ai_onnx` 0.5.1, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_onnx` with `flutter_edge_ai_onnx: ^0.5.1` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_onnx/` with `package:flutter_edge_ai_onnx/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
