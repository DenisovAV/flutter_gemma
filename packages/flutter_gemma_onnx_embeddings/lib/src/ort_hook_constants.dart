/// Public constants for the ONNX Runtime Native Assets build hook.
///
/// Kept in `lib/src/` (not inside `hook/`) so they are importable by tests
/// without triggering the native-assets build pipeline. The hook imports this
/// file and re-exports the three public `k*` symbols.
library;

/// Cache-namespace for all ONNX Runtime plain-ORT native files. Used as the
/// subdirectory name under the flutter_gemma shared cache root.
const kOnnxOrtNamespace = 'onnx_ort';

/// Base name of the main ONNX Runtime shared library. On each platform the
/// file is named `lib$kOnnxOrtMainLibName.so` / `.dylib` / `$kOnnxOrtMainLibName.dll`.
const kOnnxOrtMainLibName = 'onnxruntime';

/// SHA256 checksums keyed by the download archive filename.
///
/// Sources:
/// * Linux / macOS / Windows arm64 (GitHub releases v1.27.0): SHA256 from
///   GitHub REST API `digest` field (`GET /repos/microsoft/onnxruntime/releases/tags/v1.27.0`).
/// * Windows x64 (GitHub releases v1.26.0 — CPU zip absent from v1.27.0):
///   same GitHub REST API method.
/// * Android (Maven Central onnxruntime-android 1.26.0 — Maven lags ~4–6 weeks
///   behind GitHub; 1.27.0 not yet synced): SHA256 computed from downloaded file
///   (Maven ships SHA1 only; no published SHA256).
/// * iOS / macOS pod (CocoaPods CDN onnxruntime-c 1.27.0): BLOCKED (static
///   framework — see iOS comment below). SHA256 recorded as comment only.
///
/// Update procedure: download the new archive, run `shasum -a 256 <file>`, bump
/// the version constant(s) in `hook/build.dart`, and replace the checksum value.
const kOnnxOrtChecksums = <String, String>{
  // ── Linux x64 — GitHub releases v1.27.0 ──────────────────────────────────
  'onnxruntime-linux-x64-1.27.0.tgz':
      '547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f',

  // ── Linux arm64 — GitHub releases v1.27.0 ────────────────────────────────
  'onnxruntime-linux-aarch64-1.27.0.tgz':
      '3e4d83ac06924a32a07b6d7f91ce6f852876153fc0bbdf931bf517a140bfbe48',

  // ── macOS arm64 — GitHub releases v1.27.0 (Plan A: GitHub tgz) ───────────
  // macOS x64 is BLOCKED: no standalone tarball in v1.27.0 or later; the
  // onnxruntime-osx-x86_64-* artifact was dropped after v1.23.2. The CocoaPods
  // pod zip does contain a macos-arm64_x86_64 slice but it is a STATIC ar
  // archive (confirmed via `file` inspection) — not a Mach-O dylib. macOS x64
  // support requires a source build; deferred to a future release.
  'onnxruntime-osx-arm64-1.27.0.tgz':
      '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a',

  // ── Windows x64 — GitHub releases v1.26.0 ────────────────────────────────
  // CPU zip absent in v1.27.0 (only GPU variants present). Pin to v1.26.0.
  // Revisit when Microsoft restores the CPU zip in a future release.
  'onnxruntime-win-x64-1.26.0.zip':
      '6ebe99b5564bf4d029b6e93eac9ff423682b6212eade769e9ca3f685eaf500b4',

  // ── Windows arm64 — GitHub releases v1.27.0 ──────────────────────────────
  'onnxruntime-win-arm64-1.27.0.zip':
      'a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f',

  // ── Android arm64 — Maven Central onnxruntime-android 1.26.0 AAR ─────────
  // 1.27.0 not yet synced to Maven Central (lags ~4–6 weeks); SHA256 computed
  // from downloaded file (Maven Central ships SHA1 sidecar only).
  // Computed: shasum -a 256 onnxruntime-android-1.26.0.aar
  'onnxruntime-android-1.26.0.aar':
      '09c0780ae8d734ef2774bdf498b624729a855e6f9a8e488a0e7398a4e7396032',

  // ── iOS — CocoaPods CDN pod-archive onnxruntime-c 1.27.0 ─────────────────
  // BLOCKED: the onnxruntime.xcframework is a static framework
  // (`static_framework = true` in the podspec). Confirmed by `file` inspection:
  //   ios-arm64/onnxruntime.framework/onnxruntime: Mach-O ar archive (arm64)
  //   macos-arm64_x86_64/onnxruntime.framework/Versions/A/onnxruntime: Mach-O ar archive
  // Static `.a` archives cannot be loaded as `DynamicLoadingBundled` CodeAssets
  // via dart:ffi at runtime. iOS support via Native Assets hook is deferred until
  // Microsoft ships a dynamic xcframework build. The iOS embedding uses the
  // flutter_onnxruntime CocoaPods dependency declared in pubspec.yaml instead.
  //
  // SHA256 of pod-archive-onnxruntime-c-1.27.0.zip (for reference / future use):
  //   8c74edd600eafc3055de9e8f7a9602afee44ed516913cb5e132bca02cc34622c
  //
  // pod-archive-onnxruntime-c-1.27.0.zip — omitted intentionally (no entry →
  // hook skips iOS platform silently, same pattern as unsupported archs in the
  // litertlm hook).
};
