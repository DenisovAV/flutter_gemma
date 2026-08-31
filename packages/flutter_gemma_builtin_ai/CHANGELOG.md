## 0.2.1
- Add `BuiltInAiHuggingFaceResolver` (auto-registered from `BuiltInAiEngine`) so `resolveHuggingFace` reports that built-in OS models have no Hugging Face file (#454).
- fix: iOS/macOS builds failed on Xcode below 26.4 — `SystemLanguageModel.tokenCount` is absent from those SDKs and `#available` cannot gate a missing declaration (#460).

## 0.2.0
- Web support: Gemini Nano via the Chrome Prompt API (desktop Chrome/Edge).

## 0.1.1
- Android plugin no longer applies KGP — Flutter's Gradle plugin does (#440).
- iOS floor lowered to 15.0 — every Foundation Models call is `#available`-guarded (#441).

## 0.1.0
- Initial release: Gemini Nano (Android) + Apple Foundation Models (iOS/macOS) engine
