# flutter_gemma_diagnostics

Opt-in memory diagnostics for [flutter_gemma](https://pub.dev/packages/flutter_gemma) apps, read from the OS on Android and iOS.

## Why not RSS?

The number that decides whether your app survives a large model is not RSS.

A model whose weights are mmapped and one that copies the same weights into memory show roughly the same RSS. Only the second gets killed. Weights read from an mmapped file are clean file pages: the OS can drop them and read them again, so iOS jetsam does not charge them to your app. The same bytes copied into the heap, or into a GPU-shared allocation, are charged.

So this package reports the anonymous footprint the OS actually enforces, and the memory still available, separately.

## Usage

Add it as a dev dependency, so it stays out of release builds:

```yaml
dev_dependencies:
  flutter_gemma_diagnostics: ^0.1.0
```

```dart
import 'package:flutter_gemma_diagnostics/flutter_gemma_diagnostics.dart';

if (FlutterGemmaDiagnostics.isSupported) {
  final snapshot = await FlutterGemmaDiagnostics.memorySnapshot();
  print(snapshot.anonymousBytes); // what the OS kills on
  print(snapshot.availableBytes); // headroom left
}
```

Take a snapshot before loading a model, after loading it, and during generation. The difference is what the model costs you.

## What each field means

| Field | iOS | Android |
|---|---|---|
| `anonymousBytes` | `phys_footprint` from `task_info(TASK_VM_INFO)`, the value jetsam enforces | `Private_Dirty + SwapPss` from `/proc/self/smaps_rollup` |
| `availableBytes` | `os_proc_available_memory()`: headroom before **this app** hits its limit | `MemAvailable` from `/proc/meminfo`: available on **the whole device** |

`availableBytes` means different things on each platform because the platforms enforce memory differently. iOS gives each app a hard limit. Android has none; lmkd reacts to device-wide pressure.

Every field is nullable, and a null always means "the OS gave no number we can defend", never zero:

- `anonymousBytes` is null on Android kernels older than 4.14 (no `smaps_rollup`).
- `availableBytes` is null on the iOS simulator, where no jetsam limit applies. Apple returns 0 both for "no limit" and for "limit already exceeded", and the two cannot be told apart.

The API docs on `MemorySnapshot` list every case.

## Platforms

Android and iOS only. Jetsam and lmkd are why these numbers differ from RSS, and "will I be killed" is a mobile question. On any other platform `memorySnapshot()` throws `UnsupportedError` rather than returning empty values.

Everything is read through `dart:io` and `dart:ffi`, so the package has no Kotlin, Swift, Gradle or podspec, and no dependency on `flutter_gemma` itself: it measures the process, whichever engine runs in it.

**Status:** the Android path is covered by tests against a real Linux kernel's `/proc`, which Android shares. The iOS path's parsing is unit-tested, but the FFI calls have not yet been run on an iOS device.

## Roadmap

Planned in follow-up releases: `anonymousPeakBytes` (iOS), `fileBackedBytes` (Android), and an experimental `gpuBytes`.
