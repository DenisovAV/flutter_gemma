# flutter_gemma_mediapipe

**`flutter_gemma_mediapipe` is now [`flutter_edge_ai_mediapipe`](https://pub.dev/packages/flutter_edge_ai_mediapipe).**

This last release only re-exports `flutter_edge_ai_mediapipe` 1.0.8, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_mediapipe` with `flutter_edge_ai_mediapipe: ^1.0.8` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_mediapipe/` with `package:flutter_edge_ai_mediapipe/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
