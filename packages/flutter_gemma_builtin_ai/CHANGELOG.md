## 0.3.0
- **Breaking:** now a thin adapter over `flutter_local_ai`, which supplies every OS backend.
- **Breaking:** no longer a Flutter plugin — registrants and `Podfile.lock` regenerate; re-lock frozen CI.
- **Breaking:** macOS deployment floor raised from 10.15 to 12.0.
- **Breaking:** `lib/pigeon.g.dart` removed along with the native channel it wrapped.
- Windows support (Windows AI Foundry), through `flutter_local_ai`.
- Unsupported vision is refused at model creation, not silently dropped mid-turn.
- Every `BuiltInAi*` name and signature is unchanged; no code migration.
- `BuiltInAiAvailability` / `BuiltInAiUnavailableException` are now `LocalAi*` aliases; `toString()` prints the new name.
- Apps reaching flutter_local_ai's own API must depend on it directly; this package does not re-export it.

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
