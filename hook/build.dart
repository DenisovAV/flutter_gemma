import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';

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
  version: '0.12.0-a',
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
  checksums: {
    'litertlm-linux_x86_64.tar.gz':
        '930296b010ecc316c6b6fc4ed1c722b275b4064b59b5aad8ff7b858e9149c0d7',
    'litertlm-linux_arm64.tar.gz':
        '616b2e8cb9903bfd4ee54ca600a9a0cce38ddd16ed3e4b847a6d80e548b9aa60',
    'litertlm-windows_x86_64.tar.gz':
        'b7264091c05001ef84e53761dfee331f761e3a2362b36b28ab2ce39666400d76',
    'litertlm-macos_arm64.tar.gz':
        'a616c6996853cf095fac8c19de1d4dbf9a7434437da7f9bcc167e0e840147e10',
    'litertlm-ios_arm64.tar.gz':
        '88620e05382dcb1fdc5d2d985bfc9812f78f1422b4e9f3d1d8dfbafcf727c4ee',
    'litertlm-ios_sim_arm64.tar.gz':
        '54e067fa11ad510280e01f90260e8bda13f905a27f00e7ebc2d7ef5847868bd1',
    'litertlm-android_arm64.tar.gz':
        'a3fac90d144065a23f24b2ea03f10ad4d5025d012fdb3117e0b9afbe9f829ef7',
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
  // Skel libs are NOT bundled — device firmware provides them in /vendor/dsp/.
  androidExtraLibs: [
    'LiteRtDispatch_Qualcomm',
    'QnnHtp',
    'QnnSystem',
    'QnnHtpV73Stub',
    'QnnHtpV75Stub',
    'QnnHtpV79Stub',
    'QnnHtpV81Stub',
  ],
);

/// qdrant-edge native FFI shim — backs QdrantVectorStoreRepository on every
/// native platform (no Web — qdrant-edge depends on mmap/parking_lot which
/// don't compile to WebAssembly; Web continues to use wa-sqlite).
///
/// 0.7.1: upstream qdrant-edge now natively supports `wal_options` in
/// EdgeConfig (merged via https://github.com/qdrant/qdrant/pull/9067).
/// Vendored fork dropped; built directly from crates.io qdrant-edge 0.7.1.
const _qdrantEdgeBundle = _NativeBundle(
  namespace: 'qdrant_edge',
  version: '0.7.1',
  releaseTagPrefix: 'qdrant-edge-v',
  archivePrefix: 'qdrant-edge',
  mainLibName: 'qdrant_edge_ffi',
  // Namespaced layout: <cacheBase>/qdrant_edge/macos_arm64/...
  // No Podfile/Xcode integration needed — qdrant lives entirely behind FFI,
  // companion-free, registered as a single CodeAsset.
  markerFileName: '.version',
  checksums: {
    'qdrant-edge-linux_x86_64.tar.gz':
        'beda966f379fae26e37a574eb4803d22f97b02c399143cc839368e1247a6bd20',
    'qdrant-edge-linux_arm64.tar.gz':
        '08f3cc59f7983d71b7993f7f3abcf81e2a912a35befafab5907ff227aaf57164',
    'qdrant-edge-windows_x86_64.tar.gz':
        'b0034a10ced68470cb489058667e94c69ce2d56bc417006c559d1a0259dac005',
    'qdrant-edge-macos_arm64.tar.gz':
        'e2af47625eb48109e71e7a67abdce12f772fe503f7944cb6d9088c5c3b09b7dc',
    'qdrant-edge-ios_arm64.tar.gz':
        'a7ce2779542bada085027423ed0a719287f3ef8ce8136a201b50b78aa0b569ed',
    'qdrant-edge-ios_sim_arm64.tar.gz':
        '6f99ffc6b9e82c40e23824607b17dd1d69fba1b2b412528a75afb87f41cc97c5',
    'qdrant-edge-android_arm64.tar.gz':
        '1719a6188c054ccbc11aeed2ac7d2ca89d496b5a181767e23827ba339522835c',
  },
);

const _bundles = [_litertlmBundle, _qdrantEdgeBundle];

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

/// Wipe stale per-platform cached files when a bundle's version changes. Cheap
/// (one file read) and idempotent: if the marker matches, do nothing; if
/// missing or mismatched, delete this bundle's files in every per-platform
/// subdir and write the new marker. The next `_resolveLibDir` falls through to
/// `_downloadAndExtract` for whatever platform the build targets.
///
/// For namespaced bundles (`useFlatLayout=false`) we sweep entire per-platform
/// subdirs — nobody else owns them. For flat-layout LiteRT we delete only the
/// files listed by [_NativeBundle.ownedFileNames] so a hypothetical second
/// flat bundle wouldn't be wiped collaterally.
///
/// The marker is written even on a fresh cache root (created here if needed).
/// Without that, a second hook invocation would see freshly populated
/// platform subdirs but a missing marker, classify the cache as stale, and
/// wipe it — racing with `install_code_assets`.
void _invalidateBundleCacheIfStale(_NativeBundle bundle) {
  final cacheRoot = bundle.cacheRoot();
  if (!cacheRoot.existsSync()) {
    cacheRoot.createSync(recursive: true);
  }
  final marker = bundle.markerFile();
  final stored = marker.existsSync() ? marker.readAsStringSync().trim() : '';
  if (stored == bundle.version) return;

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
  marker.writeAsStringSync(bundle.version);
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
    _NativeBundle bundle, String dirName, Uri packageRoot, OS os) {
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
    _NativeBundle bundle, String dirName) async {
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
        'flutter_gemma: Downloading ${bundle.namespace} native libs from $url ...');

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln(
            'flutter_gemma: Download failed (HTTP ${response.statusCode})');
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

    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    final result = await Process.run(
      'tar',
      ['-xzf', archiveFile.path, '-C', targetDir.path],
    );
    if (result.exitCode != 0) {
      stderr.writeln('flutter_gemma: tar extraction failed: ${result.stderr}');
      return null;
    }

    archiveFile.deleteSync();
    stderr.writeln(
        'flutter_gemma: ${bundle.namespace} libs cached to ${targetDir.path}');
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

  _invalidateBundleCacheIfStale(bundle);

  var libDir = _resolveLibDir(bundle, dirName, input.packageRoot, os);
  libDir ??= await _downloadAndExtract(bundle, dirName);
  if (libDir == null) return;

  final prebuiltDir = libDir.uri;
  final mainFileName = _dylibFileName(os, bundle.mainLibName);
  final mainFileUri = prebuiltDir.resolve(mainFileName);
  if (!File.fromUri(mainFileUri).existsSync()) return;

  output.assets.code.add(
    CodeAsset(
      package: _packageName,
      name: 'src/native/${bundle.mainLibName}',
      linkMode: DynamicLoadingBundled(),
      file: mainFileUri,
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
        file: proxyFileUri,
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
          file: fileUri,
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
            file: fileUri,
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
            file: fileUri,
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
