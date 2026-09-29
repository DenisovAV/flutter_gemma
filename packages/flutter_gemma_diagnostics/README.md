# flutter_gemma_diagnostics

Opt-in memory diagnostics for [flutter_gemma](https://pub.dev/packages/flutter_gemma) apps, read from the OS on Android and iOS.

## Why not RSS?

RSS mixes two kinds of memory that the OS treats very differently.

Weights read from an mmapped model file are clean file pages: the OS can drop them and read them back, so they cost the app little. The same weights copied into the heap are anonymous memory the OS cannot reclaim. Both look roughly the same in RSS. On iOS, only the second counts against the jetsam limit that kills the app.

So this package reports the anonymous footprint and the memory still available, separately.

## Usage

```yaml
dependencies:
  flutter_gemma_diagnostics: ^0.1.0
```

If you only use it from `integration_test/` or `test/`, put it under `dev_dependencies` instead. Note that neither section strips anything from a release build: what keeps it out is not importing it from `lib/`.

```dart
import 'package:flutter_gemma_diagnostics/flutter_gemma_diagnostics.dart';

if (FlutterGemmaDiagnostics.isSupported) {
  final snapshot = await FlutterGemmaDiagnostics.memorySnapshot();
  print(snapshot.anonymousBytes);
  print(snapshot.availableBytes);
}
```

Take a snapshot before loading a model, after loading it, and during generation. The difference in `anonymousBytes` is what the model costs in memory the OS cannot reclaim.

## What each field means

| Field | iOS | Android |
|---|---|---|
| `anonymousBytes` | `phys_footprint` from `task_info(TASK_VM_INFO)`: the value jetsam enforces, including IOKit/GPU (Metal) allocations and compressed memory | `Private_Dirty + SwapPss` from `/proc/self/smaps_rollup`. GPU memory (KGSL, Mali, dmabuf) is mostly outside it |
| `availableBytes` | `os_proc_available_memory()`: headroom before **this app** hits its limit | `MemAvailable` from `/proc/meminfo`: available on **the whole device**, an optimistic upper bound |

The platforms enforce memory differently, and the numbers reflect it:

- **iOS** gives each app a hard limit. `anonymousBytes` is what that limit is measured against, and `availableBytes` is how far away it is.
- **Android** has no per-app limit. lmkd kills based on device-wide pressure and process priority, and starts well before `MemAvailable` reaches zero. There, `anonymousBytes` is what the app holds, not a kill threshold.

## Null versus an exception

- **A null field** means the value does not exist on this platform or OS version:
  - `anonymousBytes` on Android kernels older than 4.14, which have no `smaps_rollup`;
  - `availableBytes` on iOS when the call returns 0. Apple returns 0 both when no limit applies (the simulator) and when the limit is already exceeded, and the two cannot be told apart.
- **`MemoryReadException`** means the value should exist and the read failed: a kernel error, a permission or I/O error, or a file that lacks a field it always carries.
- **`UnsupportedError`** is thrown by `memorySnapshot()` off Android and iOS, rather than returning empty values.

## Platforms

Android and iOS. Everything is read through `dart:io` and `dart:ffi`, so the package has no Kotlin, Swift, Gradle or podspec, and no dependency on `flutter_gemma` itself: it measures the process, whichever engine runs in it.

Verified by writing 256 MiB and checking that `anonymousBytes` moves by that amount:

- Android: vivo 1933 (Android 11), Pixel 8a (Android 15) and Galaxy A34 (Android 16);
- iOS: iPhone 17 Pro simulator (iOS 26.5).

## Roadmap

Planned in follow-up releases: `anonymousPeakBytes` (iOS), `anonymousBytes` on macOS, `fileBackedBytes` (Android), and an experimental `gpuBytes`.
