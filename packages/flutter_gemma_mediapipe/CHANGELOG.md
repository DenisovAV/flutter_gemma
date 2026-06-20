## 1.0.2
- Accept `maxOutputTokens` on `createSession` for interface parity (no session-level output cap on MediaPipe; logged + ignored) (#318).

## 1.0.1
- Point `homepage` to fluttergemma.dev. No code change.

## 1.0.0
- Stable 1.0.0; spec imports redirected off the `dart:io` mobile lib for a wasm-clean web graph.

## 1.0.0-rc.1
- Initial release: MediaPipe (`.task` / `.bin`) on-device inference engine for flutter_gemma.
- Provides `MediaPipeEngine` (InferenceEngineProvider); bundles Google's MediaPipe Pod/Gradle deps.
- Android, iOS, Web (`@mediapipe/tasks-genai` CDN). No desktop (use flutter_gemma_litertlm).
