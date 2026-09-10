---
name: flutter-gemma-builtin-ai
description: Use when running the OS's own model through flutter_gemma_builtin_ai — Gemini Nano on Android or Apple Foundation Models on iOS/macOS. There is no file to download or install; the OS owns the weights, so availability must be probed at runtime and can legitimately be "not yet downloaded".
---

# The built-in OS model

`flutter_gemma_builtin_ai` runs the model the operating system already ships:
Gemini Nano through ML Kit GenAI / AICore on Android, Apple Foundation Models on
iOS and macOS.

```dart
await FlutterGemma.initialize(inferenceEngines: [BuiltInAiEngine()]);
```

## There is no model file

This is the difference from every other engine. `ModelFileType.builtIn` means
the OS owns the weights — nothing to download, nothing to bundle, no storage
budget, and `installModel` is not part of the flow. Ready-made specs are
provided:

```dart
final model = await FlutterGemma.getActiveModel(
  spec: BuiltInAiModels.geminiNano,            // or .appleFoundationModels
);
```

The trade is that availability is not yours to control.

## Probe availability before using it

```dart
final availability = await BuiltInAi.availability();
```

`BuiltInAiAvailability` has seven states, and three of them are not failures:

| State | Meaning |
| --- | --- |
| `available` | ready now |
| `downloadable` | supported, weights not fetched yet |
| `downloading` | fetch in progress |
| `unavailableDeviceUnsupported` | this hardware will never support it |
| `unavailableOsTooOld` | an OS upgrade would fix it |
| `unavailableDisabled` | turned off by the user or by policy |
| `unavailableOther` | something else |

Treat `downloadable` and `downloading` as "not yet", not as "no". `ensureReady`
triggers and awaits the download:

```dart
await BuiltInAi.ensureReady();
```

That can take minutes on first use and needs network, so drive it from an
explicit user action with visible progress — never from app start.

An unusable state throws `BuiltInAiUnavailableException`. Catch it and fall back
to a downloadable model through another engine; do not let it reach the user as
a crash.

## Android needs minSdk 26

ML Kit GenAI / AICore will not merge below API 26, so the manifest merger fails
at build time with a `uses-sdk:minSdkVersion` conflict. Raise `minSdk` to 26 in
`android/app/build.gradle(.kts)` for any app that includes this package.

## Platforms

Android, iOS and macOS only — **no web, no Windows, no Linux**. The engine
declines elsewhere rather than throwing, so a registry with another engine
registered still works.

## What you give up

The OS model is small and its behaviour is set by the platform: no choice of
weights, no LoRA, no control over quantisation, and capabilities that differ by
OS version. Use it when "zero download, zero disk" matters more than
capability; use `.litertlm` when you need a specific model.
