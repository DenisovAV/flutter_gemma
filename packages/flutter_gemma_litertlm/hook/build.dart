import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma_litertlm';

// ============================================================================
// Native bundles
// ============================================================================

/// One unit of "fetch a tarball per platform from a GitHub Release, verify
/// SHA256, extract, register the dylibs as CodeAssets". Currently there are
/// two: LiteRT-LM (inference + embedding via LiteRT C API) and qdrant-edge
/// (vector store FFI shim).
///
/// New bundles can be added by appending to [_bundles] without modifying the
/// per-platform/cache/download/extract machinery below.
class _NativeBundle {
  /// Filesystem namespace under [_cacheBaseDir]. Must be unique across bundles
  /// (e.g. `litertlm`, `qdrant_edge`).
  final String namespace;

  /// Release tag suffix; full tag is built as either `native-vX` (LiteRT) or
  /// `qdrant-edge-vX` (qdrant) — see [releaseTagPrefix].
  final String version;

  /// Prefix of the GitHub Release tag: full tag = `$releaseTagPrefix$version`.
  /// LiteRT uses `native-v`, qdrant uses `qdrant-edge-v`.
  final String releaseTagPrefix;

  /// Prefix of each platform archive: full name = `$archivePrefix-$dirName.tar.gz`.
  /// LiteRT: `litertlm`, qdrant: `qdrant-edge`.
  final String archivePrefix;

  /// SHA256 of each archive, keyed by full archive filename
  /// (e.g. `litertlm-linux_x86_64.tar.gz`).
  final Map<String, String> checksums;

  /// Name of the main shared library to register as a CodeAsset (e.g.
  /// `LiteRtLm`, `qdrant_edge_ffi`). Platform-appropriate extension is added
  /// via [_dylibFileName].
  final String mainLibName;

  /// Companion libraries to register alongside [mainLibName]. May be empty
  /// (qdrant has none). LiteRT has Metal/OpenCL/WebGPU accelerators etc.
  final List<String> companions;

  /// Companions to skip on a specific OS. LiteRT skips Apple companion
  /// dylibs on macOS because of a Native Assets install_name_tool slack
  /// issue (#247) — the Podfile post_install handles them instead.
  final Set<OS> skipCompanionsOn;

  /// Additional libraries to register on Windows only (no `lib` prefix).
  /// LiteRT: lib-prefixed copies for PE imports + DXC runtime + Intel NPU
  /// dispatch. qdrant: none.
  final List<String> windowsExtraLibs;

  /// Additional libraries to register on Android only (no `lib` prefix,
  /// `.so` suffix added automatically). LiteRT: Qualcomm NPU dispatch +
  /// QNN runtime stack (HTP + System + per-SoC Stub libs).
  final List<String> androidExtraLibs;

  /// When `true`, per-platform subdirectories live directly under
  /// [_cacheBaseDir] (`<cacheBase>/macos_arm64/...`). When `false`, they live
  /// under a per-bundle namespace (`<cacheBase>/<namespace>/macos_arm64/...`).
  ///
  /// LiteRT uses flat=true for backwards compatibility — `example/macos/Podfile`
  /// and `example/ios/Podfile` post_install scripts (plus the Xcode
  /// `project.pbxproj` build phase) hardcode the flat path. Any new bundle
  /// must use flat=false to avoid colliding with LiteRT files.
  final bool useFlatLayout;

  const _NativeBundle({
    required this.namespace,
    required this.version,
    required this.releaseTagPrefix,
    required this.archivePrefix,
    required this.checksums,
    required this.mainLibName,
    required this.markerFileName,
    this.companions = const [],
    this.skipCompanionsOn = const {},
    this.windowsExtraLibs = const [],
    this.androidExtraLibs = const [],
    this.useFlatLayout = false,
  });

  /// Name of the marker file that stores the cached bundle version. For LiteRT
  /// (flat layout) it's `.flutter_gemma_native_version` at the cache root, kept
  /// stable for backwards compatibility. For namespaced bundles it's
  /// `.version` inside the bundle's namespace subdirectory.
  final String markerFileName;

  String get releaseTag => '$releaseTagPrefix$version';
  String get releaseBase =>
      'https://github.com/DenisovAV/flutter_gemma/releases/download/$releaseTag';

  /// Directory containing this bundle's per-platform subdirectories. For flat
  /// layout that's the cache root itself; for namespaced bundles it's the
  /// `<cacheBase>/<namespace>/` subdir.
  Directory cacheRoot() => useFlatLayout
      ? _cacheBaseDir()
      : Directory('${_cacheBaseDir().path}/$namespace');

  /// Absolute path of the marker file that tracks the cached version of this
  /// bundle. Always lives at [cacheRoot] root (alongside the per-platform
  /// subdirs).
  File markerFile() => File('${cacheRoot().path}/$markerFileName');

  String archiveName(String dirName) => '$archivePrefix-$dirName.tar.gz';

  /// All filenames this bundle owns on disk inside one per-platform subdir.
  /// Used by [_invalidateBundleCacheIfStale] to wipe only this bundle's files
  /// when running in flat layout (LiteRT shares its dir with future bundles).
  Iterable<String> ownedFileNames(OS os) sync* {
    yield _dylibFileName(os, mainLibName);
    // StreamProxy is bundled with LiteRT only — but we let the file-existence
    // check at use sites decide. Listing it here is harmless either way.
    yield _dylibFileName(os, 'StreamProxy');
    for (final c in companions) {
      yield _dylibFileName(os, c);
    }
    if (os == OS.windows) {
      for (final w in windowsExtraLibs) {
        yield _dylibFileName(os, w);
      }
    }
    if (os == OS.android) {
      for (final a in androidExtraLibs) {
        yield _dylibFileName(os, a);
      }
    }
  }
}

/// LiteRT-LM native library version and release info.
///
/// 0.11.0-b adds Intel NPU dispatch bundling to the Windows tarball
/// (LiteRtDispatch.dll + OpenVino runtime + TBB, 12 extra DLLs) to enable
/// `PreferredBackend.npu` on Intel LunarLake-class chips. Windows built
/// from LiteRT-LM commit 62f7a8e (ABI-compatible with Intel NPU dispatch);
/// other 6 platforms unchanged from -a (032334d). Same optimization flags:
/// `-c opt --strip=always` (Bazel) + MSVC `/OPT:REF /OPT:ICF` (Windows).
/// Apple: vtool minos 26.2 → 16.0 patch on libGemmaModelConstraintProvider
/// (#245). Android: `-Wl,-z,max-page-size=16384` (Google Play 16KB).
const _litertlmBundle = _NativeBundle(
  namespace: 'litertlm',
  version: '0.14.0',
  releaseTagPrefix: 'native-v',
  archivePrefix: 'litertlm',
  mainLibName: 'LiteRtLm',
  // Flat layout: example/macos/Podfile, example/ios/Podfile, and the macOS
  // Xcode `project.pbxproj` build phase all hardcode
  // `${HOME}/Library/Caches/flutter_gemma/native/<platform>` without a bundle
  // namespace. Keep flat=true here until we migrate those user-facing scripts
  // in a dedicated PR (tracked: roadmap entry in CHANGELOG for 0.16.0).
  useFlatLayout: true,
  markerFileName: '.flutter_gemma_native_version',
  // 0.13.1-a: same LiteRT-LM 0.13.1 build (bundles LiteRT post-v2.1.5 main,
  // Gemma 4 E2B MTP/speculative-decoding crash fix #318) — with the NPU
  // dispatch stacks restored on Android (11 Qualcomm/QNN libs) and Windows (12
  // Intel OpenVino/TBB files), which were accidentally omitted from
  // native-v0.13.1 (broke PreferredBackend.npu on those platforms in 1.0.0).
  // Only android_arm64 + windows_x86_64 checksums changed vs 0.13.1; the other
  // 5 platforms are byte-identical. 16KB page alignment preserved (the ARM64
  // QNN libs are 16KB-aligned; the *Skel.so are DSP6 blobs, 16KB N/A).
  // 0.13.1-b: android_arm64 ONLY re-diffed vs -a — libLiteRtLm.so + the 7 other
  // LiteRt libs rebuilt from the SAME commit a0afb5a with two added C-API
  // setters (litert_lm_engine_settings_set_kernel_batch_size /
  // set_gpu_context_low_priority) exposing the GPU smooth-UI knobs for #364; the
  // 11 Qualcomm/QNN NPU libs are carried over byte-identical from -a so NPU is
  // unaffected. The other 6 platforms are byte-identical copies re-uploaded
  // under the -b tag (their checksums below are unchanged from -a).
  checksums: {
    'litertlm-linux_x86_64.tar.gz':
        '98df14ffbf8d5f14ec78f05794101077d11f0d149c25d00032a9a8e1f075e8b1',
    'litertlm-linux_arm64.tar.gz':
        '875c491a4a95713c575b98c26088ff6d8f484a0b360466f6db2f42e515ae9521',
    'litertlm-windows_x86_64.tar.gz':
        'e86ec6924e5886d164e3cc6a40ede9e5b750c2b6b952a85bd86a08c1f5a9a05e',
    'litertlm-macos_arm64.tar.gz':
        'c7fbcb8a977ac92f0a7ce19430f810eed6938a4d8324381d7f4ee4c0763073e8',
    'litertlm-ios_arm64.tar.gz':
        '174304237a400131fa673f7cfd90e05633feb7b54f08a13090ac86ae1510bff9',
    'litertlm-ios_sim_arm64.tar.gz':
        'ee619c2bfcb58f08c5f370ff34ceae39d85579619a6490b8e0372cfa04b033e7',
    'litertlm-android_arm64.tar.gz':
        'b583d49e199fe4dfdc09f44f1b4629565d784c05d33d2b109614e158da1be8bf',
  },
  companions: [
    'GemmaModelConstraintProvider',
    'LiteRtMetalAccelerator', // macOS + iOS GPU (Metal)
    'LiteRtTopKMetalSampler', // macOS + iOS device GPU sampler (Metal)
    'LiteRtGpuAccelerator', // Android GPU
    'LiteRtOpenClAccelerator', // Android OpenCL
    'LiteRtWebGpuAccelerator', // Linux/Windows GPU (WebGPU → Vulkan/DX12)
    'LiteRtTopKOpenClSampler', // Android OpenCL GPU sampler — honors seed
    'LiteRtTopKWebGpuSampler', // Linux/Windows GPU sampler
    'LiteRt', // Linux/Windows core runtime
    'webgpu_dawn', // Linux/Windows Dawn WebGPU (split to a shared lib in v0.14.0)
  ],
  // On macOS, skip the upstream Apple companion dylibs from Native Assets
  // bundling (#247). The three dylibs Google ships in
  // `prebuilt/macos_arm64/` (`libGemmaModelConstraintProvider.dylib`,
  // `libLiteRtMetalAccelerator.dylib`, `libLiteRtTopKMetalSampler.dylib`)
  // were linked without `-Wl,-headerpad_max_install_names`, leaving only
  // 32 bytes of slack in the load-commands area. Dart Native Assets'
  // JIT path (`dart run`, `dart build_runner`, `flutter test` on a pure
  // Dart library) calls `install_name_tool -id <absolute_path>` with paths
  // 80–110 chars long, which doesn't fit and aborts the whole bundling
  // step. By dropping these from the asset list, Native Assets never
  // touches them — instead `example/macos/Podfile` post_install copies
  // each dylib into `App.app/Contents/Frameworks/<X>.framework/` itself
  // and patches LiteRtLm.dylib's `LC_LOAD_DYLIB` reference to the new
  // framework path. iOS / Linux / Windows / Android are unaffected: their
  // Native Assets paths (Xcode build phases on iOS, no install_name_tool
  // on Linux/Windows/Android) don't trigger the bug.
  skipCompanionsOn: {OS.macOS},
  // Windows: LiteRtLm.dll references companion DLLs by their original
  // Google filenames with "lib" prefix (libLiteRt.dll etc.) via PE imports.
  // Native Assets uses no prefix on Windows (LiteRt.dll), so we ship both
  // names from the CI artifact — register the lib-prefixed copies here
  // so the PE loader can resolve imports at LoadLibrary time. Plus the
  // DirectXShaderCompiler runtime (WebGPU/DX12) and the Intel NPU
  // dispatch (LiteRtDispatch.dll + OpenVino + TBB).
  windowsExtraLibs: [
    'libGemmaModelConstraintProvider',
    'libLiteRt',
    'libLiteRtTopKWebGpuSampler',
    'libLiteRtWebGpuAccelerator',
    'libwebgpu_dawn', // lib-prefixed for the accelerator's PE import (v0.14.0)
    // DXC runtime
    'dxil',
    'dxcompiler',
    // Intel NPU dispatch (~30 MB, only enables PreferredBackend.npu on
    // LunarLake/PantherLake — model still loads on CPU/GPU without it).
    'LiteRtDispatch',
    'openvino',
    'openvino_intel_npu_plugin',
    'openvino_tensorflow_lite_frontend',
    'tbb12',
    'tbb12_debug',
    'tbbbind_2_5',
    'tbbbind_2_5_debug',
    'tbbmalloc',
    'tbbmalloc_debug',
    'tbbmalloc_proxy',
    'tbbmalloc_proxy_debug',
  ],
  // Android NPU: Qualcomm dispatch bridge + QNN HTP runtime + per-SoC Stubs.
  // Extracted from Google AI Edge Gallery APKs (no Qualcomm account needed);
  // ABI verified against litert_dispatch.h at LiteRT commit d865fd82.
  // sm8550=V73, sm8650=V75, sm8750=V79, sm8850=V81.
  // Skel libs (DSP-side code) extracted from Google AI Edge Gallery APKs.
  // Stub libs are the CPU-side bridge; Skel libs run on Hexagon DSP via FastRPC.
  androidExtraLibs: [
    'LiteRtDispatch_Qualcomm',
    'QnnHtp',
    'QnnSystem',
    'QnnHtpV73Stub',
    'QnnHtpV73Skel',
    'QnnHtpV75Stub',
    'QnnHtpV75Skel',
    'QnnHtpV79Stub',
    'QnnHtpV79Skel',
    'QnnHtpV81Stub',
    'QnnHtpV81Skel',
  ],
);

const _bundles = [_litertlmBundle];

// ============================================================================
// Per-platform name resolution
// ============================================================================

/// Resolve prebuilt directory name for the given OS + architecture.
/// iOS distinguishes device vs simulator via IOSSdk.
String? _prebuiltDirName(OS os, Architecture arch, {IOSSdk? iOSSdk}) {
  if (os == OS.iOS) {
    // Only arm64 is supported. On Apple Silicon Macs, Flutter still invokes
    // the hook for x86_64 simulator slices; returning null skips them so
    // Native Assets's lipo step doesn't try to merge two arm64-only inputs
    // and fail with "same architectures and can't be in the same fat file".
    if (arch != Architecture.arm64) return null;
    if (iOSSdk == IOSSdk.iPhoneSimulator) {
      return 'ios_sim_arm64';
    }
    return 'ios_arm64';
  }
  final archName = switch (arch) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    _ => null,
  };
  if (archName == null) return null;
  final osName = switch (os) {
    OS.macOS => 'macos',
    OS.linux => 'linux',
    OS.windows => 'windows',
    OS.android => 'android',
    _ => null,
  };
  if (osName == null) return null;
  return '${osName}_$archName';
}

// ============================================================================
// Cache layout
// ============================================================================

/// Platform-appropriate base directory for all native caches. Per-bundle
/// subdirectories live underneath (e.g. `<cacheBase>/litertlm/macos_arm64/`).
///
/// The path is **not** versioned because example/macos/Podfile and
/// example/ios/Podfile read companion dylibs from a stable location;
/// version invalidation happens via per-bundle `.version` marker files
/// (see [_invalidateBundleCacheIfStale]).
Directory _cacheBaseDir() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (Platform.isWindows) {
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
    return Directory('$localAppData\\flutter_gemma\\native');
  }
  if (Platform.isMacOS) {
    return Directory('$home/Library/Caches/flutter_gemma/native');
  }
  return Directory('$home/.cache/flutter_gemma/native');
}

/// Reads the JSON marker for [bundle]. Returns null if absent, malformed, or
/// LEGACY plain-text (pre-protocol) — all treated as "not present" so the next
/// step re-fetches and rewrites the marker as JSON (self-heal).
({String version, String owner})? _readMarker(_NativeBundle bundle) {
  final m = bundle.markerFile();
  if (!m.existsSync()) return null;
  try {
    final decoded = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
    final v = decoded['version'];
    final o = decoded['owner'];
    if (v is String && o is String) return (version: v, owner: o);
    return null;
  } catch (_) {
    return null; // legacy plain-text or corrupt → treat as absent
  }
}

/// Writes the JSON marker {version, owner}. owner = this hook's _packageName.
/// COMMIT POINT: call LAST, only after the dylib files are fully in place.
void _writeMarker(_NativeBundle bundle) {
  bundle.markerFile().writeAsStringSync(
    jsonEncode({'version': bundle.version, 'owner': _packageName}),
  );
}

/// Wipe stale per-platform cached files when a bundle's version changes. Cheap
/// (one marker read) and idempotent: if the JSON marker matches this bundle's
/// version, do nothing; if missing, legacy plain-text, or a mismatched version,
/// delete this bundle's files in every per-platform subdir. The next
/// `_resolveLibDir` falls through to `_downloadAndExtract` for whatever platform
/// the build targets. WIPE-ONLY — does NOT write the marker; `_writeMarker` is
/// the commit point in `_processBundle`, called only AFTER the dylib is in place
/// (so an interrupted fetch leaves no marker → clean refetch next build).
///
/// For namespaced bundles (`useFlatLayout=false`) we sweep entire per-platform
/// subdirs — nobody else owns them. For flat-layout LiteRT we delete only the
/// files listed by [_NativeBundle.ownedFileNames] so a hypothetical second
/// flat bundle wouldn't be wiped collaterally.
void _invalidateBundleCacheIfStale(_NativeBundle bundle) {
  final cacheRoot = bundle.cacheRoot();
  if (!cacheRoot.existsSync()) {
    cacheRoot.createSync(recursive: true);
  }
  final stored = _readMarker(bundle);
  if (stored != null && stored.version == bundle.version) return;

  final platformPattern = RegExp(r'^(linux|macos|ios|android|windows)_');
  for (final entity in cacheRoot.listSync()) {
    if (entity is! Directory) continue;
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (!platformPattern.hasMatch(name)) continue;

    if (bundle.useFlatLayout) {
      // Shared dir — delete only files this bundle owns. Iterate every OS
      // (we don't know which one the subdir was populated for; just attempt
      // all names — `deleteSync` is a no-op when the file is absent).
      for (final os in OS.values) {
        for (final fileName in bundle.ownedFileNames(os)) {
          final f = File('${entity.path}/$fileName');
          if (f.existsSync()) {
            f.deleteSync();
          }
        }
      }
    } else {
      // Exclusive dir — wipe the whole platform subdir, faster + cleaner.
      entity.deleteSync(recursive: true);
    }
  }
}

// ============================================================================
// Dynamic-library file naming
// ============================================================================

/// Dylib filename for [name] on [os]: `lib<name>.so/dylib` on Unix-like
/// systems, `<name>.dll` on Windows. The lib prefix is applied unconditionally
/// for now — both LiteRT and qdrant use it on every Unix-like target.
String _dylibFileName(OS os, String name) {
  return switch (os) {
    OS.windows => '$name.dll',
    OS.macOS || OS.iOS => 'lib$name.dylib',
    _ => 'lib$name.so',
  };
}

bool _hasMainLib(Directory dir, _NativeBundle bundle, OS os) {
  if (!dir.existsSync()) return false;
  final fileName = _dylibFileName(os, bundle.mainLibName);
  return File('${dir.path}/$fileName').existsSync();
}

/// Try to resolve libs from a directory. Returns the directory if the bundle's
/// main lib exists. Search order:
///   1. local `native/<bundle-namespace>/prebuilt/<dirName>/` inside the
///      package — useful for in-tree development.
///   2. cached `<cacheBase>/<bundle-namespace>/<dirName>/` from a previous
///      `_downloadAndExtract`.
Directory? _resolveLibDir(
  _NativeBundle bundle,
  String dirName,
  Uri packageRoot,
  OS os,
) {
  // Local prebuilts use a per-bundle directory layout under `native/`.
  // LiteRT historically uses `native/litert_lm/prebuilt/`. For new bundles
  // we use `native/<namespace>/prebuilt/`.
  final localPath = bundle.namespace == 'litertlm'
      ? 'native/litert_lm/prebuilt/$dirName/'
      : 'native/${bundle.namespace}/prebuilt/$dirName/';
  final localDir = Directory.fromUri(packageRoot.resolve(localPath));
  if (_hasMainLib(localDir, bundle, os)) return localDir;

  final cacheDir = Directory('${bundle.cacheRoot().path}/$dirName');
  if (_hasMainLib(cacheDir, bundle, os)) return cacheDir;

  return null;
}

// ============================================================================
// Download + verify + extract
// ============================================================================

Future<Directory?> _downloadAndExtract(
  _NativeBundle bundle,
  String dirName,
) async {
  final archiveName = bundle.archiveName(dirName);
  final expectedChecksum = bundle.checksums[archiveName];
  if (expectedChecksum == null) {
    // No checksum registered — silently skip (mirrors LiteRT-LM behavior for
    // unsupported targets like android_x86_64). Build proceeds without this
    // CodeAsset; runtime will fail at first use with a clear "no such file"
    // dlopen error.
    return null;
  }

  final cacheRoot = bundle.cacheRoot();
  final targetDir = Directory('${cacheRoot.path}/$dirName');
  final archiveFile = File('${cacheRoot.path}/$archiveName');

  try {
    if (!cacheRoot.existsSync()) {
      cacheRoot.createSync(recursive: true);
    }

    final url = '${bundle.releaseBase}/$archiveName';
    stderr.writeln(
      'flutter_gemma: Downloading ${bundle.namespace} native libs from $url ...',
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln(
          'flutter_gemma: Download failed (HTTP ${response.statusCode})',
        );
        return null;
      }
      final sink = archiveFile.openWrite();
      await response.pipe(sink);
    } finally {
      client.close();
    }

    final bytes = await archiveFile.readAsBytes();
    final actualChecksum = sha256.convert(bytes).toString();
    if (actualChecksum != expectedChecksum) {
      stderr.writeln('flutter_gemma: Checksum mismatch for $archiveName!');
      stderr.writeln('  Expected: $expectedChecksum');
      stderr.writeln('  Actual:   $actualChecksum');
      archiveFile.deleteSync();
      return null;
    }
    stderr.writeln('flutter_gemma: Checksum verified ($archiveName)');

    // Extract into a sibling temp dir on the SAME filesystem (under cacheRoot),
    // then atomically rename into place. A torn/interrupted extract leaves only
    // the temp dir (cleaned in finally), never a half-populated targetDir.
    final tmpDir = Directory('${cacheRoot.path}/.tmp-$dirName-$pid');
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    tmpDir.createSync(recursive: true);
    try {
      final result = await Process.run('tar', [
        '-xzf',
        archiveFile.path,
        '-C',
        tmpDir.path,
      ]);
      if (result.exitCode != 0) {
        stderr.writeln(
          'flutter_gemma: ${bundle.namespace} extract failed: ${result.stderr}',
        );
        return null;
      }
      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      tmpDir.renameSync(targetDir.path); // atomic on same FS
    } finally {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    }
    archiveFile.deleteSync();
    stderr.writeln(
      'flutter_gemma: ${bundle.namespace} libs cached to ${targetDir.path}',
    );
    return targetDir;
  } catch (e) {
    stderr.writeln('flutter_gemma: ${bundle.namespace} download failed: $e');
    if (archiveFile.existsSync()) archiveFile.deleteSync();
    return null;
  }
}

// ============================================================================
// Per-bundle processing — register CodeAssets from resolved libDir
// ============================================================================

/// Cross-package coordination for a shared native bundle. Inspects the marker:
///   - (present: true)  → exact (bundle, version) already cached → dedup
///   - (present: false) → caller fetches (absent, legacy, OR same-owner upgrade)
///   - THROWS           → a DIFFERENT owner placed a DIFFERENT version (skew).
/// Call FIRST in _processBundle. The existing _resolveLibDir/_hasMainLib do the
/// actual from-cache dedup; the guard's load-bearing job is the throw on skew.
({bool present}) _guardAndCheckPresent(_NativeBundle bundle) {
  final existing = _readMarker(bundle);
  // absent / legacy → fetch.
  if (existing == null) return (present: false);
  // exact match → dedup.
  if (existing.version == bundle.version) return (present: true);
  // same-owner upgrade → fetch.
  if (existing.owner == _packageName) return (present: false);
  throw StateError(
    'Native library conflict for "${bundle.namespace}": '
    'this package ($_packageName) needs version ${bundle.version}, '
    'but "${existing.owner}" already placed version ${existing.version} '
    'in the shared cache (${bundle.cacheRoot().path}). '
    'Align the ${bundle.namespace} bundle version across these packages '
    "(each package's hook/build.dart pins it).",
  );
}

Future<void> _processBundle({
  required _NativeBundle bundle,
  required BuildInput input,
  required BuildOutputBuilder output,
  required OS os,
  required String dirName,
}) async {
  // Skip the bundle entirely if it has no checksum for this platform.
  // Both bundles use this as the "is this target supported" gate.
  if (!bundle.checksums.containsKey(bundle.archiveName(dirName))) return;

  // Cross-package version-skew guard (throws on a different owner declaring a
  // different version of this shared bundle). Match/absent/same-owner are no-ops
  // here — _resolveLibDir below does the actual dedup; this call exists so the
  // THROW happens before any fetch/wipe on a skew.
  _guardAndCheckPresent(bundle);

  // Sole owner of libLiteRtLm now; the single-registrant marker is vestigial
  // (cache-dedup only).
  //
  // Single-registrant: only the bundle's owner (the first hook to write the
  // marker) registers the shared CodeAssets. A non-owner package sharing the
  // same bundle (e.g. embeddings sharing litertlm's libLiteRtLm) ensures the
  // cache is populated (dedup/download below) but must NOT re-register the same
  // dylib — Native Assets errors on a duplicate bundled filename, and both FFI
  // loaders open it by a FIXED basename (libLiteRtLm.so / LiteRtLm.framework),
  // so exactly one package must bundle it. At runtime the non-owner's
  // DynamicLibrary.open(filename) resolves the owner-bundled dylib.
  //
  // KNOWN LIMITATION (orphaned-owner edge case): the owner is persisted in the
  // shared-cache marker ACROSS builds. A Dart build hook is sandboxed — it sees
  // only its own packageRoot; BuildInput.assets/metadata expose ONLY direct
  // dependencies (hooks config.dart, ToBuildHooks dartdoc), and litertlm /
  // embeddings deliberately don't depend on each other (embeddings is
  // autonomous). So a hook CANNOT learn the current build's package set and
  // CANNOT recompute the registrant per-build. If the recorded owner is later
  // dropped from the app's deps and the survivor rebuilds without `flutter
  // clean`, the survivor reads the stale owner, skips registration, and nobody
  // bundles the dylib → an opaque dlopen "no such file" at first use. Fix:
  // `flutter clean` + delete the flutter_gemma native cache (see each package's
  // README troubleshooting). Upstream deliberately chose "one registrant + error
  // on conflict, no auto-dedup" (dart-lang/native#190, flutter#158214).
  //
  // Capture the owner state BEFORE _writeMarker below can overwrite it: a
  // non-owner dedup must not clobber the marker's owner to itself.
  final existingOwner = _readMarker(bundle)?.owner;
  final iAmRegistrant = existingOwner == null || existingOwner == _packageName;

  _invalidateBundleCacheIfStale(bundle);

  var libDir = _resolveLibDir(bundle, dirName, input.packageRoot, os);
  libDir ??= await _downloadAndExtract(bundle, dirName);
  if (libDir == null) return;

  final prebuiltDir = libDir.uri;
  final mainFileName = _dylibFileName(os, bundle.mainLibName);
  final mainFileUri = prebuiltDir.resolve(mainFileName);
  if (!File.fromUri(mainFileUri).existsSync()) return;

  // Commit point: marker written only after the dylib is confirmed in place.
  // Gated on iAmRegistrant so a non-owner dedup never clobbers the owner.
  if (iAmRegistrant) _writeMarker(bundle);

  // Non-owner stops here: cache is populated, but the owner registers the
  // shared CodeAssets to avoid a duplicate bundled-filename error.
  if (!iAmRegistrant) return;

  // Flutter's native-assets pipeline declares every `CodeAsset.file` as a
  // build OUTPUT and every `output.dependencies` entry as a build INPUT (see
  // flutter_tools build_system/targets/native_assets.dart `DartBuild`).
  // Registering a dylib straight from `prebuiltDir` (the global cache, which we
  // also list as a dependency below) makes the output dylib live INSIDE an
  // input directory. Xcode then takes a directoryTreeSignature over that input
  // dir which includes the output dylib, so the macOS "Flutter Assemble" Run
  // Script ends up depending on its own output → "Cycle inside Flutter
  // Assemble" (and "located outside of the allowed root paths" warnings).
  //
  // Fix: copy each dylib into the hook's `outputDirectory` (an allowed root
  // that never overlaps the cache dependency dir) and register the CodeAsset
  // from there. The cache dir stays an input-only dependency for rebuild
  // detection. Copies are size-guarded so the hook only rewrites on change.
  //
  // APPLE-ONLY: the "Cycle inside Flutter Assemble" self-loop is an Xcode
  // mechanism (the Run Script's directoryTreeSignature over an input dir that
  // contains the output dylib). Windows (MSBuild) and Linux (Ninja) have no
  // such cycle, so staging there solves nothing — and on Windows it actively
  // breaks the PE loader: it splits the main `LiteRtLm.dll` (staged) away from
  // its dynamically-loaded companion DLLs (samplers / Intel-NPU dispatch /
  // openvino / tbb) that stay in the cache, so a `dlopen` of a companion on
  // cancel/close cannot find it and hangs. So stage ONLY on the Apple
  // toolchain, where the cycle actually occurs; elsewhere register straight
  // from the cache (the layout the loader expects), keeping every file
  // consistent regardless of which list it came from.
  Uri stage(Uri srcUri) {
    if (os != OS.macOS && os != OS.iOS) return srcUri;
    final src = File.fromUri(srcUri);
    final destUri = input.outputDirectory.resolve(srcUri.pathSegments.last);
    final dest = File.fromUri(destUri);
    if (!dest.existsSync() || dest.lengthSync() != src.lengthSync()) {
      dest.parent.createSync(recursive: true);
      src.copySync(destUri.toFilePath());
    }
    return destUri;
  }

  output.assets.code.add(
    CodeAsset(
      package: _packageName,
      name: 'src/native/${bundle.mainLibName}',
      linkMode: DynamicLoadingBundled(),
      file: stage(mainFileUri),
    ),
  );

  // StreamProxy companion (LiteRT only — a tiny C lib that copies callback
  // strings to heap). Lives in the same tarball, registered by convention.
  // Other bundles can ignore it by simply not shipping a `StreamProxy.*` file.
  final proxyFileName = _dylibFileName(os, 'StreamProxy');
  final proxyFileUri = prebuiltDir.resolve(proxyFileName);
  if (File.fromUri(proxyFileUri).existsSync()) {
    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: 'src/native/StreamProxy',
        linkMode: DynamicLoadingBundled(),
        file: stage(proxyFileUri),
      ),
    );
  }

  // Companion libraries (accelerators, samplers, etc.).
  final skipCompanions = bundle.skipCompanionsOn.contains(os);
  for (final name in bundle.companions) {
    if (skipCompanions) continue;
    final fileName = _dylibFileName(os, name);
    final fileUri = prebuiltDir.resolve(fileName);
    if (File.fromUri(fileUri).existsSync()) {
      output.assets.code.add(
        CodeAsset(
          package: _packageName,
          name: 'src/native/$name',
          linkMode: DynamicLoadingBundled(),
          file: stage(fileUri),
        ),
      );
    }
  }

  // Windows-only extras (lib-prefixed companions for PE imports, DXC, NPU).
  if (os == OS.windows) {
    for (final name in bundle.windowsExtraLibs) {
      final fileName = _dylibFileName(os, name);
      final fileUri = prebuiltDir.resolve(fileName);
      if (File.fromUri(fileUri).existsSync()) {
        output.assets.code.add(
          CodeAsset(
            package: _packageName,
            name: 'src/native/$name',
            linkMode: DynamicLoadingBundled(),
            file: stage(fileUri),
          ),
        );
      }
    }
  }

  // Android-only extras (Qualcomm NPU dispatch + QNN runtime stack).
  if (os == OS.android) {
    for (final name in bundle.androidExtraLibs) {
      final fileName = _dylibFileName(os, name);
      final fileUri = prebuiltDir.resolve(fileName);
      if (File.fromUri(fileUri).existsSync()) {
        output.assets.code.add(
          CodeAsset(
            package: _packageName,
            name: 'src/native/$name',
            linkMode: DynamicLoadingBundled(),
            file: stage(fileUri),
          ),
        );
      }
    }
  }

  output.dependencies.add(prebuiltDir);
}

// ============================================================================
// Entry point
// ============================================================================

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    // Supported platforms: desktop + iOS + Android.
    // Web uses MediaPipe JS + wa-sqlite (dart:ffi blocked in WASM).
    if (os != OS.macOS &&
        os != OS.linux &&
        os != OS.windows &&
        os != OS.iOS &&
        os != OS.android) {
      return;
    }

    final arch = codeConfig.targetArchitecture;
    final iOSSdk = os == OS.iOS ? codeConfig.iOS.targetSdk : null;
    final dirName = _prebuiltDirName(os, arch, iOSSdk: iOSSdk);
    if (dirName == null) return; // Unsupported arch (e.g. arm32), skip.

    for (final bundle in _bundles) {
      await _processBundle(
        bundle: bundle,
        input: input,
        output: output,
        os: os,
        dirName: dirName,
      );
    }
  });
}
