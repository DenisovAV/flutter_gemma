# flutter_gemma_diagnostics

**`flutter_gemma_diagnostics` is now [`flutter_edge_ai_diagnostics`](https://pub.dev/packages/flutter_edge_ai_diagnostics).**

This last release only re-exports `flutter_edge_ai_diagnostics` 0.2.0, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_diagnostics` with `flutter_edge_ai_diagnostics: ^0.2.0` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_diagnostics/` with `package:flutter_edge_ai_diagnostics/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
