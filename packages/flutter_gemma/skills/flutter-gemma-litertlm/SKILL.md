---
name: flutter-gemma-litertlm
description: Use when the app runs .litertlm models through flutter_gemma_litertlm — the default engine on all six platforms. Covers the 1024-token KV cache floor that crashes below it, the Android minSdk 30 requirement, and backend selection.
---

# The .litertlm engine

`flutter_gemma_litertlm` is the main inference path: Dart FFI straight into the
LiteRT-LM C API on Android, iOS, macOS, Windows and Linux, plus a web arm. No
JVM, no gRPC, no separate process.

```dart
await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,   // required — the default is `task`
).fromNetwork(url).install();
```

## maxTokens below 1024 crashes, it does not truncate

Every supported `.litertlm` model bakes `kv_cache_max_len = 1024`. A `maxTokens`
below that underflows the native KV-cache resize and tensor allocation fails at
generation with a message naming an internal executor file.

Measured on a Pixel 8a (CPU): 100 / 256 / 512 crash; 1024 and 4096 work.

The engine now clamps values below 1024 upward and logs a warning, but do not
rely on that. Pass a real context size and cap the reply with
`maxOutputTokens` on the session — that one is `.litertlm`-only and is the
correct knob for reply length.

## Android needs minSdk 30

`libLiteRtLm.so` uses `pthread_cond_clockwait` and `sem_clockwait`, which are
API-30-only Bionic symbols. On API 29 it fails at `dlopen`, not at build time.
Set `minSdk 30` in `android/app/build.gradle(.kts)` for any app that runs
`.litertlm`.

Only `arm64-v8a` is shipped. A build implying other ABIs produces an APK
without the native library.

## Backends

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 1024,
  preferredBackend: PreferredBackend.gpu,
);
```

| | Android | iOS | Desktop | Web |
| --- | --- | --- | --- | --- |
| `cpu` | yes | yes | yes | no |
| `gpu` | yes | device only | yes | required |
| `npu` | Snapdragon | no | Windows, Intel Lunar/Panther Lake | no |

Passing an explicit backend disables fallback — if that backend cannot load the
model, it fails rather than quietly trying another. Leaving it null tries GPU
then CPU. Some models bake a constraint: the 12B build declares
`section_backend_constraint: gpu` and an explicit `cpu` on it simply fails.

**iOS Simulator is CPU-only.** Metal there has a 256 MB single-allocation cap
and model weights exceed it. Test GPU on a real device.

## Desktop is `.litertlm` only

There is no `.task` support on macOS, Windows or Linux. Windows GPU needs
`dxil.dll` and `dxcompiler.dll`, and Windows NPU needs Intel Lunar/Panther Lake
silicon — both ship inside the bundled native archive, nothing to install.

## Native libraries are fetched at build time

`hook/build.dart` downloads a per-platform archive from a pinned GitHub release
and verifies its SHA256 (Native Assets). Nothing is committed to the repo and
nothing ships in the pub package, so a first build needs network access.

If a build fails on a missing symbol after upgrading, the shared-bundle owner
marker went stale: delete
`~/Library/Caches/flutter_gemma/native/.flutter_gemma_native_version` and run
`flutter clean`.

## Web is an early preview

Text only. No vision, audio, thinking, function calling or LoRA on the
`.litertlm` web arm — those work on native. Web is also GPU-only.
