# Spike S2: ORT-GenAI desktop two-archive fetch + iOS xcframework codesign recipe

**Date:** 2026-06-21
**ORT-GenAI version pinned:** 0.14.0 (released 2026-05-29)
**Matching plain-ORT requirement:** `onnxruntime >= 1.26.0` (confirmed from PyPI wheel metadata)
**Prior art:** Builds on S1 (`docs/research/spikes/S1-plain-ort-bundles.md`) for plain-ORT archive details.
**Scope:** Concrete fetch recipes for Win-x64, macOS-arm64, Linux-x64 (desktop two-archive), and iOS
xcframework (codesign/slice status). Determines whether iOS generation ships in v1 or defers to v2.

---

## iOS VERDICT (read first)

**VERDICT: iOS generation — feasible for v1, with a note on the maccatalyst slice.**

- Simulator slice: **YES — CONFIRMED** (`ios-arm64_x86_64-simulator` is present in the zip).
- Issue #1335 (symlink/codesign defect): **CLOSED** (last updated 2025-03-26). The maccatalyst slice
  still stores symlinks as data entries (not zip symlink flags), but the slice structure is present.
  Phase C must re-sign the maccatalyst slice with `codesign` after extraction. Device and simulator
  slices use the flat iOS framework layout and are unaffected by the symlink issue.
- ORT bundling on iOS: **statically compiled in** — no separate plain-ORT fetch required on iOS.
- Escalation: **NOT required.** iOS generation is feasible for v1. Continue.

---

## 1. ORT-GenAI v0.14.0 release asset naming convention

Assets use version-first naming: `onnxruntime-genai-<version>-<platform>.<ext>`.
This is the opposite of plain-ORT's `onnxruntime-<platform>-<version>.<ext>` convention — the hook
must not assume a shared pattern.

---

## 2. Desktop two-archive recipe

### 2a. ORT-GenAI archives (first archive per platform)

SHA256 values are from the GitHub Releases REST API `digest` field
(`GET /repos/microsoft/onnxruntime-genai/releases/tags/v0.14.0`, `assets[].digest`, strip `sha256:` prefix).

| Platform | Asset name | Size (bytes) | SHA256 |
|---|---|---|---|
| Windows x64 | `onnxruntime-genai-0.14.0-win-x64.zip` | 16,739,566 | `8a303e52dc7be8fb2a5331929af451a25ac59774102d7fd09ef673adc85c5ebf` |
| macOS arm64 | `onnxruntime-genai-0.14.0-osx-arm64.tar.gz` | 3,518,415 | `56583c98e3939d2cfd5a3812471be44017ce2752776d389015ff583a8d758312` |
| Linux x64 | `onnxruntime-genai-0.14.0-linux-x64.tar.gz` | 55,924,971 | `7b37f13619ee01263278fb1c24a950e219d75c9fa90586b1623d3e8bab9076b0` |
| Linux arm64 | `onnxruntime-genai-0.14.0-linux-arm64.tar.gz` | 55,322,240 | `7d4d1ad8f0f956968f95a1344d49443f8172cab5b0f69f28ffd833e82e89044b` |
| Windows arm64 | `onnxruntime-genai-0.14.0-win-arm64.zip` | 16,300,846 | `b6daeedb6395406e4cefbd6577a0d2196611e360086f7767c153b1d4b3cb3f1b` |

Download URL pattern: `https://github.com/microsoft/onnxruntime-genai/releases/download/v0.14.0/<asset-name>`

Additional EP variants exist (cuda, dml, winml) — v1 fetches CPU variants only (no suffix).

### 2b. In-archive directory layout (confirmed by inspection)

All three desktop archives use the same nested layout:
```
onnxruntime-genai-0.14.0-<platform>/
  lib/
    libonnxruntime-genai.dylib   (macOS — 9.6 MB)
    libonnxruntime-genai.so      (Linux — ~183 MB uncompressed)
    onnxruntime-genai.dll        (Windows — 5.9 MB)
    onnxruntime-genai.lib        (Windows import lib — 37 KB)
    onnxruntime-genai.pdb        (Windows debug symbols — 51 MB; skip in production)
  include/
    ort_genai.h
    ort_genai_c.h
  LICENSE, README.md, SECURITY.md, ThirdPartyNotices.txt
```

The hook must strip the top-level version directory when extracting (use a `*/lib/` glob).

### 2c. Plain-ORT dependency per platform (second archive)

This is the critical distinction: ORT is handled differently per platform.

| Platform | ORT bundling | Plain-ORT needed? | Source |
|---|---|---|---|
| macOS arm64 | **NOT bundled** — `libonnxruntime.dylib` dlopened at runtime (bare name) | **YES** | See S1: `onnxruntime-osx-arm64-1.27.0.tgz` or `pod-archive-onnxruntime-c-1.27.0.zip` |
| Windows x64 | **NOT bundled** — `onnxruntime.dll` loaded via `LoadLibraryExA` at runtime | **YES** | See S1: `onnxruntime-win-x64-1.26.0.zip` (CPU zip absent in v1.27.0) |
| Linux x64 | **Statically linked** — ORT compiled into `libonnxruntime-genai.so` (183 MB) | **NO** | — |
| Linux arm64 | **Statically linked** (same pattern as Linux x64) | **NO** | — |
| Windows arm64 | **NOT bundled** (same pattern as Windows x64 — small DLL, LoadLibrary) | **YES** | See S1: `onnxruntime-win-arm64-1.27.0.zip` |

**Evidence for macOS:** `otool -L libonnxruntime-genai.dylib` shows NO `libonnxruntime.dylib` entry —
but `strings` reveals the literal string `"libonnxruntime.dylib"` plus `"Attempting to dlopen %s"` and
`"Error while dlopen: %s"` format strings. Runtime loading confirmed. The dylib is only 9.6 MB, which
rules out static bundling.

**Evidence for Windows:** `strings onnxruntime-genai.dll` shows `"onnxruntime.dll"` + `"LoadLibraryExA"`.
DLL is 5.9 MB, confirming no static bundling.

**Evidence for Linux:** `readelf -d libonnxruntime-genai.so` NEEDED list contains only system libs
(`libdl.so.2`, `libpthread.so.0`, `libgcc_s.so.1`, `libstdc++.so.6`, `libc.so.6`, etc.) — no
`libonnxruntime.so`. Uncompressed size is ~183 MB, consistent with static embedding of the full ORT stack.

**ORT compatibility requirement:** `onnxruntime >= 1.26.0` (from PyPI `onnxruntime-genai 0.14.0`
wheel metadata, `requires_dist` field).

### 2d. WHERE libonnxruntime.* must land (dynamic loading resolution)

**macOS:** `libonnxruntime-genai.dylib` uses `dlopen("libonnxruntime.dylib", ...)` with a bare filename
(no path component). On macOS, bare-name `dlopen` searches: `DYLD_LIBRARY_PATH`, `DYLD_FALLBACK_LIBRARY_PATH`,
`/usr/local/lib`, `/usr/lib`. The `@rpath`-based search does NOT apply to bare-name dlopen.

The hook must place `libonnxruntime.dylib` in the **same directory** as `libonnxruntime-genai.dylib` AND
also output `libonnxruntime.1.27.0.dylib` (the versioned copy from the ORT tarball). Then, before
returning from the Native Assets hook, call `install_name_tool` to add an `LC_RPATH` pointing to the
output lib directory on `libonnxruntime-genai.dylib`. Alternatively, use
`DYLD_LIBRARY_PATH=$(dirname libonnxruntime-genai.dylib)` at process launch (Flutter dev mode only).

**Recommended hook action for macOS:**
1. Extract both archives to the same `<build_output>/lib/` dir.
2. Run `install_name_tool -add_rpath @loader_path /path/to/libonnxruntime-genai.dylib` after extraction.
   This makes `dlopen("libonnxruntime.dylib")` resolve via the `@loader_path`-appended rpath. Note:
   `dlopen` with a bare name does NOT use LC_RPATH by default on macOS — the hook may need to use
   `dlopen("@rpath/libonnxruntime.dylib")` if possible, or simply ensure both dylibs are co-located
   in `DYLD_FALLBACK_LIBRARY_PATH`. **Verify this with a runtime probe before wiring Phase C.**

**Windows:** `LoadLibraryExA("onnxruntime.dll")` searches: the directory of the loading DLL, then
`System32`, then `PATH`. Place `onnxruntime.dll` + `onnxruntime_providers_shared.dll` in the same
directory as `onnxruntime-genai.dll`. This is the standard Windows DLL co-location pattern and works
without any manifest changes.

**Linux:** No second archive needed — ORT is already compiled in.

### 2e. Native-Assets CodeAsset registration

Both ORT-GenAI and (on macOS/Windows) plain-ORT register as `CodeAsset`s in `hook/build.dart`:

```dart
// ORT-GenAI (all desktop platforms)
buildOutput.assets.code.add(
  CodeAsset(
    package: 'flutter_gemma_onnx',
    name: 'onnxruntime_genai',
    file: Uri.file('path/to/libonnxruntime-genai.dylib'),
    linkMode: DynamicLoadingBundled(),
    os: OS.macOS,
    architecture: Architecture.arm64,
  ),
);

// Plain ORT (macOS, Windows, Windows arm64 — NOT Linux)
buildOutput.assets.code.add(
  CodeAsset(
    package: 'flutter_gemma_onnx',
    name: 'onnxruntime',
    file: Uri.file('path/to/libonnxruntime.dylib'),
    linkMode: DynamicLoadingBundled(),
    os: OS.macOS,
    architecture: Architecture.arm64,
  ),
);
```

On Linux, only the ORT-GenAI asset is registered (plain ORT is statically compiled in).

---

## 3. iOS xcframework recipe

### 3a. Release asset

| Field | Value |
|---|---|
| Asset name | `onnxruntime-genai-ios-0.14.0.zip` |
| Size | 50,122,319 bytes (~47.8 MB) |
| SHA256 | `6734735af0827d503031a9e17e034cafeb9b54311d333b3dc6aa1ed73476137f` |
| Download URL | `https://github.com/microsoft/onnxruntime-genai/releases/download/v0.14.0/onnxruntime-genai-ios-0.14.0.zip` |
| SHA256 source | GitHub Releases REST API `digest` field (confirmed match) |

### 3b. xcframework slice list (confirmed from Info.plist inspection)

Top-level name: `onnxruntime-genai.xcframework`

| LibraryIdentifier | SupportedPlatform | Variant | Architectures | Binary | Size |
|---|---|---|---|---|---|
| `ios-arm64` | ios | (device — no variant) | arm64 | `onnxruntime-genai.framework/onnxruntime-genai` | ~33 MB |
| `ios-arm64_x86_64-simulator` | ios | simulator | arm64 + x86_64 (fat) | `onnxruntime-genai.framework/onnxruntime-genai` | ~71 MB |
| `ios-arm64_x86_64-maccatalyst` | ios | maccatalyst | arm64 + x86_64 (fat) | `onnxruntime-genai.framework/Versions/A/onnxruntime-genai` | ~69 MB |

**Simulator slice:** CONFIRMED PRESENT. `ios-arm64_x86_64-simulator` covers both Apple Silicon
simulators (arm64) and Intel Mac simulators (x86_64). Local iOS-sim testing is NOT blocked.

**ORT bundling on iOS:** Statically compiled into each slice binary. No `libonnxruntime.*` file appears
anywhere in the zip. Slice binary sizes (33–71 MB) are consistent with both ORT-GenAI and ORT compiled
in. **No separate plain-ORT fetch is needed for iOS.**

### 3c. Issue #1335 status — symlink/codesign defect

**Status: CLOSED** (Microsoft repository, last updated 2025-03-26).

**Original defect:** When the zip was created without `zip --symlinks`, the maccatalyst slice's
`Versions/Current`, `Headers`, and top-level binary symlinks were stored as regular files (tiny stub
files: 1, 24, 34 bytes) rather than true zip symlinks. This caused code-signing to fail with
"bundle format is ambiguous" because the expected macOS framework structure (versioned directory with
symlinks at the root) was broken.

**Status in v0.14.0:** `unzip -v` reports zero symlink-flagged entries in the maccatalyst slice, but
the symlink content strings ARE present as the file contents of the tiny entries. Whether these are
valid symlinks depends on unzip behavior with platform zip flags. The device and simulator slices use
the flat iOS framework layout (no `Versions/` hierarchy) and are **not affected**.

**Practical decision for the hook:**
- **Device slice (`ios-arm64`):** Extract and sign as-is — flat layout, no symlink issue.
- **Simulator slice (`ios-arm64_x86_64-simulator`):** Extract and sign as-is — flat layout, no symlink issue.
- **Maccatalyst slice:** The hook does NOT need to support Mac Catalyst for v1 (Flutter does not
  target Mac Catalyst; macOS is handled via the macOS desktop path). Skip or strip this slice.

**Strip/re-sign steps (if maccatalyst slice is ever needed):**
```bash
# After unzip:
cd onnxruntime-genai.xcframework/ios-arm64_x86_64-maccatalyst/onnxruntime-genai.framework/
# Re-create symlinks:
ln -sf Versions/A Versions/Current
ln -sf Versions/Current/Headers Headers
ln -sf "Versions/Current/onnxruntime-genai" onnxruntime-genai
# Re-sign the framework:
codesign --deep -s - onnxruntime-genai.xcframework/ios-arm64_x86_64-maccatalyst/
```

For v1, the hook extracts only the device and simulator slices (or the full xcframework but skips
maccatalyst codesigning). Phase C should test with `xcodebuild -create-xcframework` if repackaging
is required, or embed the xcframework directly.

### 3d. Native-Assets CodeAsset registration for iOS

ORT-GenAI on iOS is a **dynamic framework** (`.framework` bundle with a Mach-O dylib inside), not a
standalone `.dylib`. Native Assets `CodeAsset` with `DynamicLoadingBundled()` covers this.

```dart
// iOS device
buildOutput.assets.code.add(
  CodeAsset(
    package: 'flutter_gemma_onnx',
    name: 'onnxruntime_genai',
    file: Uri.file('path/to/onnxruntime-genai.xcframework/ios-arm64/onnxruntime-genai.framework/onnxruntime-genai'),
    linkMode: DynamicLoadingBundled(),
    os: OS.iOS,
    architecture: Architecture.arm64,
  ),
);
// iOS simulator (arm64 slice; x86_64 slice is also in the same fat binary)
buildOutput.assets.code.add(
  CodeAsset(
    package: 'flutter_gemma_onnx',
    name: 'onnxruntime_genai',
    file: Uri.file('path/to/onnxruntime-genai.xcframework/ios-arm64_x86_64-simulator/onnxruntime-genai.framework/onnxruntime-genai'),
    linkMode: DynamicLoadingBundled(),
    os: OS.iOS,
    architecture: Architecture.arm64, // Flutter picks the right slice from the fat binary
  ),
);
```

No plain-ORT CodeAsset needed for iOS.

---

## 4. Summary table: per-platform fetch plan

| Platform | Genai archive | Plain-ORT archive | ORT in genai? | Hook action |
|---|---|---|---|---|
| Win x64 | `onnxruntime-genai-0.14.0-win-x64.zip` | `onnxruntime-win-x64-1.26.0.zip` (from S1) | No — LoadLibrary | Co-locate DLLs, 2 CodeAssets |
| Win arm64 | `onnxruntime-genai-0.14.0-win-arm64.zip` | `onnxruntime-win-arm64-1.27.0.zip` (from S1) | No — LoadLibrary | Co-locate DLLs, 2 CodeAssets |
| macOS arm64 | `onnxruntime-genai-0.14.0-osx-arm64.tar.gz` | `onnxruntime-osx-arm64-1.27.0.tgz` (from S1) | No — dlopen | Co-locate dylibs + install_name_tool, 2 CodeAssets |
| Linux x64 | `onnxruntime-genai-0.14.0-linux-x64.tar.gz` | — (statically linked) | YES | 1 CodeAsset only |
| Linux arm64 | `onnxruntime-genai-0.14.0-linux-arm64.tar.gz` | — (statically linked) | YES | 1 CodeAsset only |
| iOS (device + sim) | `onnxruntime-genai-ios-0.14.0.zip` | — (statically linked) | YES | xcframework CodeAssets |
| Android | (not this spike — see AAR path) | — | TBD | separate spike |

---

## 5. SHA256 constants for the hook

```dart
const _genaiChecksums = {
  // ORT-GenAI 0.14.0 — from GitHub Releases API digest field
  'onnxruntime-genai-0.14.0-win-x64.zip':
      '8a303e52dc7be8fb2a5331929af451a25ac59774102d7fd09ef673adc85c5ebf',
  'onnxruntime-genai-0.14.0-win-arm64.zip':
      'b6daeedb6395406e4cefbd6577a0d2196611e360086f7767c153b1d4b3cb3f1b',
  'onnxruntime-genai-0.14.0-osx-arm64.tar.gz':
      '56583c98e3939d2cfd5a3812471be44017ce2752776d389015ff583a8d758312',
  'onnxruntime-genai-0.14.0-linux-x64.tar.gz':
      '7b37f13619ee01263278fb1c24a950e219d75c9fa90586b1623d3e8bab9076b0',
  'onnxruntime-genai-0.14.0-linux-arm64.tar.gz':
      '7d4d1ad8f0f956968f95a1344d49443f8172cab5b0f69f28ffd833e82e89044b',
  'onnxruntime-genai-ios-0.14.0.zip':
      '6734735af0827d503031a9e17e034cafeb9b54311d333b3dc6aa1ed73476137f',
};

// Plain-ORT checksums — see S1 for full list; relevant entries:
const _ortChecksums = {
  'onnxruntime-osx-arm64-1.27.0.tgz':
      '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a',
  'onnxruntime-win-x64-1.26.0.zip':   // CPU zip absent in v1.27.0 — pin to 1.26.0
      '6ebe99b5564bf4d029b6e93eac9ff423682b6212eade769e9ca3f685eaf500b4',
  'onnxruntime-win-arm64-1.27.0.zip':
      'a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f',
  // Linux: no plain-ORT needed (statically linked)
  // iOS: no plain-ORT needed (statically linked)
};
```

---

## 6. Open items for Phase C (hook implementation)

1. **macOS dlopen resolution must be probed.** `libonnxruntime-genai.dylib` dlopens
   `"libonnxruntime.dylib"` by bare name. `install_name_tool -add_rpath @loader_path` alone may not
   be sufficient because bare-name `dlopen` on macOS does not walk `LC_RPATH`. The hook may need to
   relink the dylib with `install_name_tool -change libonnxruntime.dylib @rpath/libonnxruntime.dylib`
   (changing the embedded string in the genai dylib) or fall back to placing both dylibs in a directory
   on `DYLD_FALLBACK_LIBRARY_PATH`. **Requires a runtime probe in Phase C before finalizing.**

2. **macOS versioned dylib symlink.** The plain-ORT macOS tarball provides `lib/libonnxruntime.dylib`
   (symlink) and `lib/libonnxruntime.1.27.0.dylib` (versioned). Extract both; ensure the symlink is
   preserved. The genai dylib dlopens the unversioned name.

3. **macOS x64 (Intel Mac) support.** No standalone `onnxruntime-osx-x86_64-*.tgz` exists in ORT
   v1.27.0 (dropped after v1.23.2). Plain ORT for macOS x64 must come from the CocoaPods pod zip
   (`pod-archive-onnxruntime-c-1.27.0.zip`, which includes a fat `macos-arm64_x86_64` slice) — but
   verify that slice is native macOS (not Mac Catalyst). See S1 review follow-up item #1.

4. **No ORT-GenAI prebuilt for macOS x64.** There is no
   `onnxruntime-genai-0.14.0-osx-x86_64.tar.gz` or `osx-universal2` in v0.14.0 releases.
   ORT-GenAI on macOS is arm64 only in v0.14.0. Intel Mac support is deferred or requires build-from-source.

5. **iOS maccatalyst slice:** Skip for v1. No Flutter target uses Mac Catalyst via the iOS path.

6. **Windows PDB files:** The Windows zip includes `onnxruntime-genai.pdb` at 51 MB. Do not include
   this in the production Native Assets output — add an explicit filter in the hook.

7. **ORT version alignment:** ORT-GenAI 0.14.0 requires `onnxruntime >= 1.26.0`. Plain-ORT 1.26.0 is
   used for Windows x64 (CPU zip absent in v1.27.0). Plain-ORT 1.27.0 is used for other platforms.
   This minor version skew is acceptable given `>= 1.26.0` compatibility.

---

## 7. Escalation note

**Not required.** iOS generation is feasible for v1:
- Official xcframework exists, both device and simulator slices are present.
- Issue #1335 is closed; device and simulator slices are unaffected.
- Maccatalyst slice re-sign is needed only if Mac Catalyst is targeted (not a v1 requirement).
- ORT is statically bundled in the iOS xcframework — no second archive fetch.

Phase C may proceed with iOS included in v1 scope. Phase D2 flag: **iOS-in-v1 = YES**.
