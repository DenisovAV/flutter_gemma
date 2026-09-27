# flutter_gemma_speech

**`flutter_gemma_speech` is now [`flutter_edge_ai_speech`](https://pub.dev/packages/flutter_edge_ai_speech).**

This last release only re-exports `flutter_edge_ai_speech` 0.6.0, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_speech` with `flutter_edge_ai_speech: ^0.6.0` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_speech/` with `package:flutter_edge_ai_speech/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
