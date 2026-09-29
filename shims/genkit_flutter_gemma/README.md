# genkit_flutter_gemma

**`genkit_flutter_gemma` is now [`genkit_flutter_edge_ai`](https://pub.dev/packages/genkit_flutter_edge_ai).**

This last release only re-exports `genkit_flutter_edge_ai` 0.6.2, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `genkit_flutter_gemma` with `genkit_flutter_edge_ai: ^0.6.2` in `pubspec.yaml`.
2. Replace `package:genkit_flutter_gemma/` with `package:genkit_flutter_edge_ai/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
