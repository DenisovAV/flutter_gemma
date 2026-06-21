# Spike S1: Plain ONNX Runtime native bundle layout + checksums per platform

**Date:** 2026-06-21
**ORT version pinned:** 1.27.0 (released 2026-06-19 — latest stable)
**Scope:** Plain ONNX Runtime inference runtime only — NOT onnxruntime-genai / ORT-GenAI.
**Purpose:** Determine what to fetch per platform for the `flutter_gemma_onnx_embeddings` Native Assets build hook.

---

## Prior art (DO NOT re-derive)

`docs/research/2026-06-21-onnx-genai-open-questions-resolved.md` covers ORT-GenAI bundle facts.
This doc covers only the **plain ORT** side (needed as a separate fetch per desktop/Android platform because ORT-GenAI archives contain ONLY `libonnxruntime-genai.*` — the main `libonnxruntime.*` is an external dynamic dependency).

---

## 1. Per-platform table

### Android arm64-v8a

| Field | Value |
|---|---|
| Channel | Maven Central |
| Artifact | `com.microsoft.onnxruntime:onnxruntime-android` |
| Version | **1.26.0** (v1.27.0 NOT yet synced to Maven Central as of 2026-06-21; Maven lags ~4-6 weeks) |
| Download URL | `https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.26.0/onnxruntime-android-1.26.0.aar` |
| Archive size | 43,596,581 bytes (~41.6 MB) |
| Key files inside AAR | `jni/arm64-v8a/libonnxruntime.so`, `jni/arm64-v8a/libonnxruntime4j_jni.so`, `classes.jar` (Java bindings), `headers/` (C/C++ headers). ALL ABIs bundled (arm64-v8a, armeabi-v7a, x86, x86_64). |
| Native `.so` bundled? | YES — the AAR contains the full native library, not just Java bindings |
| SHA256 sidecar | DOES NOT EXIST (HTTP 404) |
| SHA1 sidecar | EXISTS — `https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.26.0/onnxruntime-android-1.26.0.aar.sha1` → `8064b1e65f35a3cad2214324c2dbeceadcc6ecc7` |
| MD5 sidecar | EXISTS — `143ebdf1b816d37395308ac0c768194b` |
| Usable for hook? | YES with caveat: version lags GitHub; SHA1 only (not SHA256) from Maven |

### iOS (device + simulator)

| Field | Value |
|---|---|
| Channel | `download.onnxruntime.ai` (Microsoft CDN, mirrored from CocoaPods spec) |
| Pod | `onnxruntime-c` 1.27.0 (`static_framework = true`) |
| Download URL | `https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.27.0.zip` |
| Archive size | 55,588,338 bytes (~53 MB) |
| Key files inside | `onnxruntime.xcframework/ios-arm64/` (device static framework), `onnxruntime.xcframework/ios-arm64_x86_64-simulator/` (Simulator fat binary), `onnxruntime.xcframework/macos-arm64_x86_64/` (macOS slice — also usable for macOS) |
| Framework type | Static (`static_framework = true`) |
| Minimum iOS | 15.1 |
| SHA256 published? | NO — no `.sha256`, `.sha1`, or checksums file at `download.onnxruntime.ai` |
| GitHub release iOS asset? | NOT available in GitHub Releases for v1.27.0 — CocoaPods CDN is the only official channel |
| Usable for hook? | YES — URL is stable and Microsoft-controlled; SHA256 must be hardcoded (compute once from downloaded file) |

**CRITICAL — iOS simulator slice: CONFIRMED PRESENT.**
The `ios-arm64_x86_64-simulator` directory is confirmed inside the xcframework zip. Local simulator testing is NOT blocked. No source build required.

### macOS arm64

| Field | Value |
|---|---|
| Channel | GitHub releases |
| Archive name | `onnxruntime-osx-arm64-1.27.0.tgz` |
| Download URL | `https://github.com/microsoft/onnxruntime/releases/download/v1.27.0/onnxruntime-osx-arm64-1.27.0.tgz` |
| Archive size | 32,485,368 bytes (~31 MB) |
| Key files inside | `lib/libonnxruntime.dylib` (symlink), `lib/libonnxruntime.1.27.0.dylib` (versioned), `include/onnxruntime/` (C headers) |
| SHA256 | `545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a` |
| SHA256 source | GitHub REST API `digest` field: `GET /repos/microsoft/onnxruntime/releases/tags/v1.27.0`, `assets[].digest` → `sha256:<hex>` (strip prefix) |
| Usable for hook? | YES — stable URL, SHA256 available |

**macOS x64 — BLOCKED.** The `onnxruntime-osx-x86_64-*.tgz` artifact was dropped from GitHub releases starting v1.24.1; last available in v1.23.2. There is no official prebuilt `libonnxruntime.dylib` for x86_64 macOS in v1.27.0 from any Microsoft channel. The NuGet `Microsoft.ML.OnnxRuntime` v1.27.0 is a managed package, not a raw dylib. The `onnxruntime-c` CocoaPods zip DOES include `macos-arm64_x86_64` (a fat binary — see iOS row above) — this is a viable source for both macOS archs if the hook unpacks from the same pod zip.

**Recommendation for macOS:** Fetch the `onnxruntime-c` CocoaPods zip (same file as iOS) which contains a macOS fat binary. Unpack `onnxruntime.xcframework/macos-arm64_x86_64/` — this covers both arm64 and x64. Avoids needing a separate macOS tarball. One file, two platforms.

### Windows x64

| Field | Value |
|---|---|
| Channel | GitHub releases (v1.26.0 — see note) |
| Archive name | `onnxruntime-win-x64-1.26.0.zip` |
| Download URL | `https://github.com/microsoft/onnxruntime/releases/download/v1.26.0/onnxruntime-win-x64-1.26.0.zip` |
| Archive size | 75,675,381 bytes (~72 MB) |
| Key DLLs inside | `onnxruntime.dll`, `onnxruntime_providers_shared.dll` (both required for CPU EP) |
| SHA256 | `6ebe99b5564bf4d029b6e93eac9ff423682b6212eade769e9ca3f685eaf500b4` |
| SHA256 source | GitHub REST API `digest` field (same pattern as macOS) |
| Usable for hook? | YES with caveat: version pinned to 1.26.0 (CPU zip absent in v1.27.0 GitHub releases) |

**v1.27.0 status:** `onnxruntime-win-x64-1.27.0.zip` DOES NOT EXIST in GitHub Releases v1.27.0. Only GPU variants (`_gpu_cuda12`, `_gpu_cuda13`) are present. The CPU runtime for v1.27.0 is only via NuGet `Microsoft.ML.OnnxRuntime 1.27.0` which is not a raw DLL zip. Pin to v1.26.0 for now; revisit if Microsoft restores the CPU zip in a future release.

**Windows arm64 (v1.27.0):** `onnxruntime-win-arm64-1.27.0.zip` EXISTS — 78,593,089 bytes (~75 MB), SHA256: `a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f`.

### Linux x64

| Field | Value |
|---|---|
| Channel | GitHub releases |
| Archive name | `onnxruntime-linux-x64-1.27.0.tgz` |
| Download URL | `https://github.com/microsoft/onnxruntime/releases/download/v1.27.0/onnxruntime-linux-x64-1.27.0.tgz` |
| Archive size | 8,831,605 bytes (~8.4 MB) |
| Key files inside | `lib/libonnxruntime.so` (symlink), `lib/libonnxruntime.so.1.27.0` (versioned), `lib/libonnxruntime_providers_shared.so`, `include/onnxruntime/` |
| SONAME | `libonnxruntime.so.1.27.0` (NOT `libonnxruntime.so.1`) |
| SHA256 | `547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f` |
| SHA256 source | GitHub REST API `digest` field |
| Usable for hook? | YES — stable URL, SHA256 available |

Linux aarch64 bonus: `onnxruntime-linux-aarch64-1.27.0.tgz` — 7,797,972 bytes (~7.4 MB), SHA256: `3e4d83ac06924a32a07b6d7f91ce6f852876153fc0bbdf931bf517a140bfbe48`.

### Web WASM

| Field | Value |
|---|---|
| Channel | npm |
| Package | `onnxruntime-web` 1.27.0 |
| WASM files | `ort-wasm-simd-threaded.wasm`, `ort-wasm-simd-threaded.jsep.wasm` (WebGPU/WebNN), `.jspi.wasm`, `.asyncify.wasm` |
| npm sha512 integrity | `sha512-ogDLsqIozHZwifPuN37OproAo0byX6t43/bP8GzeZWBWD6MOGExswFAx3up4NS/vvWBOg2u2PXomDt3rMmdQSg==` |
| Dart FFI usable? | NO — `dart:ffi` is unavailable in WASM targets |
| In-scope for Native Assets hook? | OUT OF SCOPE — no FFI path; requires separate `dart:js_interop` implementation |

**Web is OUT OF SCOPE for a `hook/build.dart`.** Dart Native Assets does not run on Web (`dart:ffi` blocked). Web support would require a separate `dart:js_interop` binding to `onnxruntime-web` npm — a distinct implementation track.

---

## 2. Decision: direct-fetch vs re-host

**DECISION: Fetch directly from official Microsoft channels. Do NOT re-host.**

### Rationale

| Factor | Analysis |
|---|---|
| **License** | ONNX Runtime is MIT — no redistribution restriction. Re-hosting is legally fine. |
| **URL stability** | GitHub release URLs (`/releases/download/v<tag>/<file>`) are permanent. Maven Central URLs are permanent. `download.onnxruntime.ai` is Microsoft-controlled and stable. |
| **SHA256 availability** | GitHub releases: YES — `digest` field on every asset via REST API (confirmed for all v1.27.0 GitHub-hosted assets). Hardcode values in hook. Maven Central: SHA1 only (SHA256 sidecar absent). iOS CDN: no checksum published — must compute+hardcode once. |
| **Re-hosting burden** | Requires a new `checksums_onnx.txt` + GitHub release asset upload on every ORT release. ORT releases frequently (~every 6 weeks). Adds manual steps. |
| **Version skew** | Maven Central lags by ~4-6 weeks. Re-hosting would allow pinning all platforms to the same version — but at the cost of re-hosting maintenance. Acceptable to pin Android to a slightly older version that is available. |
| **Hook complexity** | Direct-fetch with hardcoded SHA256 constants is the same pattern as `flutter_gemma_litertlm/hook/build.dart`. No extra infrastructure. |

The `DenisovAV/flutter_gemma` re-hosting pattern was chosen for LiteRT-LM because Google does not publish standalone prebuilt `.so` archives on a stable URL — the hook needs re-packaged tarballs. For plain ORT, Microsoft DOES publish stable release archives directly on GitHub/Maven/CocoaPods CDN, making re-hosting unnecessary.

**One exception:** if checksums for iOS or the Maven Android artifact are unacceptable (SHA1 only), the hook can fetch those two artifacts and hardcode SHA256 values computed once at hook-authoring time. This is the minimum-overhead approach.

---

## 3. For the hook — `NativeLibraryConfig` field values

A future `packages/flutter_gemma_onnx_embeddings/hook/build.dart` can model its `_NativeBundle` (or equivalent) with these values:

```
namespace:        'onnxruntime'
version:          '1.27.0'      // pin; update per release
releaseTagPrefix: 'v'           // GitHub tag: 'v1.27.0'
archivePrefix:    'onnxruntime' // e.g. 'onnxruntime-linux-x64-1.27.0.tgz'
mainLibName:      'onnxruntime' // -> libonnxruntime.so / libonnxruntime.dylib / onnxruntime.dll
companions:       ['onnxruntime_providers_shared']  // needed on Linux and Windows
useFlatLayout:    false         // use namespaced layout (no LiteRT collision)
windowsExtraLibs: []            // no Windows extras beyond companion
androidExtraLibs: []            // no Android NPU extras for plain ORT v1
skipCompanionsOn: {}            // no skip needed (companion is a .dll/.so, not Apple dylib)
```

**Per-platform download sources** (not one unified GitHub release):

| Platform | Source | Archive pattern |
|---|---|---|
| `android_arm64` | Maven Central | `https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/<version>/onnxruntime-android-<version>.aar` |
| `ios_arm64` + `ios_sim_arm64` | `download.onnxruntime.ai` | `https://download.onnxruntime.ai/pod-archive-onnxruntime-c-<version>.zip` |
| `macos_arm64` + `macos_x86_64` | `download.onnxruntime.ai` (same zip as iOS) | `https://download.onnxruntime.ai/pod-archive-onnxruntime-c-<version>.zip` |
| `linux_x86_64` | GitHub releases | `https://github.com/microsoft/onnxruntime/releases/download/v<version>/onnxruntime-linux-x64-<version>.tgz` |
| `linux_arm64` | GitHub releases | `https://github.com/microsoft/onnxruntime/releases/download/v<version>/onnxruntime-linux-aarch64-<version>.tgz` |
| `windows_x86_64` | GitHub releases (v1.26.0) | `https://github.com/microsoft/onnxruntime/releases/download/v<version>/onnxruntime-win-x64-<version>.zip` |
| `web` | OUT OF SCOPE | — |

**Note:** The multi-source nature (GitHub + Maven + CocoaPods CDN) means the `_NativeBundle` abstraction from `flutter_gemma_litertlm/hook/build.dart` does not map 1:1. The ONNX hook will need a per-platform URL resolver rather than the single `releaseBase` URL pattern. This is a design difference from LiteRT — the hook author should plan for a `_platformUrl(String dirName)` function instead of a prefix + archive name formula.

**Checksums to hardcode** (as of 2026-06-21, ORT 1.27.0 / 1.26.0 where noted):

```dart
const _checksums = {
  // Android arm64 — Maven Central onnxruntime-android 1.26.0 AAR
  // (SHA1 from Maven; SHA256 must be computed from downloaded file)
  'onnxruntime-android-1.26.0.aar': '<COMPUTE_SHA256_FROM_DOWNLOAD>',

  // iOS + macOS — CocoaPods CDN pod-archive onnxruntime-c 1.27.0
  // (no published SHA256; compute from downloaded file)
  'pod-archive-onnxruntime-c-1.27.0.zip': '<COMPUTE_SHA256_FROM_DOWNLOAD>',

  // Linux x64 — GitHub releases v1.27.0
  'onnxruntime-linux-x64-1.27.0.tgz':
      '547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f',

  // Linux arm64 — GitHub releases v1.27.0
  'onnxruntime-linux-aarch64-1.27.0.tgz':
      '3e4d83ac06924a32a07b6d7f91ce6f852876153fc0bbdf931bf517a140bfbe48',

  // macOS arm64 — GitHub releases v1.27.0 (alternative if not using pod zip)
  'onnxruntime-osx-arm64-1.27.0.tgz':
      '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a',

  // Windows x64 — GitHub releases v1.26.0 (CPU zip absent in v1.27.0)
  'onnxruntime-win-x64-1.26.0.zip':
      '6ebe99b5564bf4d029b6e93eac9ff423682b6212eade769e9ca3f685eaf500b4',

  // Windows arm64 — GitHub releases v1.27.0
  'onnxruntime-win-arm64-1.27.0.zip':
      'a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f',
};
```

---

## 4. Platform status summary

| Platform | Status | Notes |
|---|---|---|
| Android arm64-v8a | OK | Maven Central 1.26.0; SHA1 from Maven; libonnxruntime.so inside AAR |
| iOS arm64 (device) | OK | CocoaPods CDN; static framework; no published SHA256 |
| iOS arm64 (simulator) | OK — simulator slice CONFIRMED | Same zip as device; `ios-arm64_x86_64-simulator` confirmed present |
| macOS arm64 | OK | GitHub releases v1.27.0 with SHA256 |
| macOS x64 | CONCERN | No standalone tarball in v1.27.0; use pod zip fat binary (same as iOS source) |
| Windows x64 | CONCERN | CPU zip absent in v1.27.0; pin to v1.26.0 |
| Windows arm64 | OK | GitHub releases v1.27.0 with SHA256 |
| Linux x64 | OK | GitHub releases v1.27.0 with SHA256 |
| Linux arm64 | OK | GitHub releases v1.27.0 with SHA256 |
| Web WASM | OUT OF SCOPE | dart:ffi not available on Web; separate JS interop track |

No platform is BLOCKED for embeddings-only usage. macOS x64 and Windows x64 have concerns (missing standalone v1.27.0 tarballs) but feasible workarounds exist.

## Review follow-ups (carry into hook Task A2/C2 — do NOT skip)

Two Important items from the S1 review that the hook implementer MUST resolve
before the hook is ship-ready (not blockers for the spike, but load-bearing for A2/C2):

1. **Mac Catalyst vs native macOS slice.** The CocoaPods `onnxruntime-c` xcframework's
   `macos-arm64_x86_64` slice may be a Mac **Catalyst** framework (`macabi` archs in the
   official build settings), NOT a native macOS dylib suitable for Flutter `dart:ffi`.
   **Action in A2:** download the pod zip, inspect the `.xcframework` Info.plist +
   `otool -l` the binary to confirm it is a native macOS dylib (LC_BUILD_VERSION platform
   == MACOS, not MACCATALYST). If it is Catalyst-only, macOS x64 must come from another
   source (e.g. build-from-source, or the universal2 tarball from an older release, or
   accept arm64-only macOS for v1). Verify BEFORE wiring the hook's macOS path.

2. **Two SHA256 values are unresolved placeholders.** Android (Maven ships SHA1 only) and
   iOS/macOS (CocoaPods CDN ships no checksum). The `_checksums` map cannot ship with
   `<COMPUTE_SHA256_FROM_DOWNLOAD>` entries — the project REQUIRES SHA256 verification.
   **Action in A2:** download each artifact once, compute its SHA256, hardcode it in the
   hook's `_checksums` map. Re-host-on-our-releases remains the fallback if Microsoft's
   source URLs prove unstable (then we control the checksum file directly).
