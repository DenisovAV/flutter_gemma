# flutter_gemma_litertlm

**`flutter_gemma_litertlm` is now [`flutter_edge_ai_litertlm`](https://pub.dev/packages/flutter_edge_ai_litertlm).**

This last release only re-exports `flutter_edge_ai_litertlm` 1.9.0, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_litertlm` with `flutter_edge_ai_litertlm: ^1.9.0` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_litertlm/` with `package:flutter_edge_ai_litertlm/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
