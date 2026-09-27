# flutter_gemma

**`flutter_gemma` is now [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai).**

This last release only re-exports `flutter_edge_ai` 1.12.0, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma` with `flutter_edge_ai: ^1.12.0` in `pubspec.yaml`.
2. Replace `package:flutter_gemma/` with `package:flutter_edge_ai/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
