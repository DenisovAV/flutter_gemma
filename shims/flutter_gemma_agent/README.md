# flutter_gemma_agent

**`flutter_gemma_agent` is now [`flutter_edge_ai_agent`](https://pub.dev/packages/flutter_edge_ai_agent).**

This last release only re-exports `flutter_edge_ai_agent` 0.3.0, so an app that bumps its
version keeps compiling — with a deprecation warning on the import. Nothing
new will be published under this name.

To move over:

1. Replace `flutter_gemma_agent` with `flutter_edge_ai_agent: ^0.3.0` in `pubspec.yaml`.
2. Replace `package:flutter_gemma_agent/` with `package:flutter_edge_ai_agent/` in your imports.

Models, vector stores and platform setup carry over unchanged. The full guide:
https://flutteredge.ai/docs/migration
