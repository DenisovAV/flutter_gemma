# flutter_gemma_rag_sqlite

**`flutter_gemma_rag_sqlite` is now [`flutter_edge_ai_sqlite`](https://pub.dev/packages/flutter_edge_ai_sqlite).**

This last release only re-exports `flutter_edge_ai_sqlite` 1.4.0, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_rag_sqlite` with `flutter_edge_ai_sqlite: ^1.4.0` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_rag_sqlite/` with `package:flutter_edge_ai_sqlite/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
