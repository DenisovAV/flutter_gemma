import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';
const _mainLibName = 'LiteRtLm';

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
const _nativeVersion = '0.11.0-b';
const _releaseTag = 'native-v$_nativeVersion';
const _releaseBase =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/$_releaseTag';

/// SHA256 checksums for each platform archive.
/// Updated when new native libs are published to GitHub Release.
const _checksums = <String, String>{
  'litertlm-linux_x86_64.tar.gz':
      '79583513cbbdda784b1714c1068a1fdd0f8133364868574ec3334af8d0eee056',
  'litertlm-linux_arm64.tar.gz':
      'bab26bf420316ef2f4037ffced1470a18cbb6ee6cda069fc0ae8a5f8eb882bfb',
  'litertlm-windows_x86_64.tar.gz':
      '2291db8d4cc104d695b589a179ef04f0c955f906264d625ed4f16babe13d952e',
  'litertlm-macos_arm64.tar.gz':
      'fa3138c9f97b6ba3c19f620c29439207d38566598fff06cc55ff115ade17f8e8',
  'litertlm-ios_arm64.tar.gz':
      'eae0d0ef8b81eeb6e6e0b69a482513f47b371ec2f410f571763538a5d23c7607',
  'litertlm-ios_sim_arm64.tar.gz':
      'f92b8fcb3627c82c9398f39bcf6851a46e97f9565d5341d454390802bf1ffd78',
  'litertlm-android_arm64.tar.gz':
      '9712d55d1a248ad8834531f2d937a9bbf2feceaad8a1d352ef5f63a4dedb8f17',
};

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

/// Platform-appropriate cache directory. Path is NOT versioned because
/// example/macos/Podfile and example/ios/Podfile read companion dylibs
/// from this same location (Native Assets cache → app bundle Frameworks/);
/// keeping a single canonical path means the Podfile doesn't need to know
/// `_nativeVersion`.
///
/// Cache invalidation on a native bump is handled by `_invalidateCacheIfStale`
/// (called from the build hook) which compares a `.version` marker file in
/// the cache root against `_nativeVersion`, and wipes the per-platform
/// subdirs on mismatch so the next `_downloadAndExtract` repopulates them.
Directory _cacheDir() {
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
  // Linux and others
  return Directory('$home/.cache/flutter_gemma/native');
}

/// Wipe stale platform subdirs when `_nativeVersion` changes. The check is
/// cheap (one file read) and idempotent: if the marker matches, do nothing;
/// if missing or mismatched, delete every platform subdir under `_cacheDir()`
/// and write the new marker. The next `_resolveLibDir` will fall through to
/// `_downloadAndExtract` for whatever platform the build is targeting.
///
/// The marker is written even on a fresh cache root (created here if needed).
/// Without that, a second invocation of the build hook (or any other Native
/// Assets pass) would see the freshly populated platform subdir but a missing
/// marker, classify the cache as stale, and wipe it — racing with
/// `install_code_assets` (`Cannot copy file ... libLiteRtLm.so ... No such
/// file or directory` on a clean CI runner cache).
void _invalidateCacheIfStale() {
  final cacheBase = _cacheDir();
  if (!cacheBase.existsSync()) {
    cacheBase.createSync(recursive: true);
  }
  final marker = File('${cacheBase.path}/.flutter_gemma_native_version');
  final stored = marker.existsSync() ? marker.readAsStringSync().trim() : '';
  if (stored == _nativeVersion) return;
  for (final entity in cacheBase.listSync()) {
    if (entity is Directory) {
      // Wipe per-platform subdirs (linux_x86_64/, macos_arm64/, etc.) but
      // leave anything else untouched (e.g. cache dirs from other tools
      // could share this root in the future).
      final name = entity.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      if (RegExp(r'^(linux|macos|ios|android|windows)_').hasMatch(name)) {
        entity.deleteSync(recursive: true);
      }
    }
  }
  marker.writeAsStringSync(_nativeVersion);
}

/// Archive name for a given platform directory.
String _archiveName(String dirName) => 'litertlm-$dirName.tar.gz';

/// Try to resolve libs from a directory. Returns the directory if main lib exists.
Directory? _resolveLibDir(String dirName, Uri packageRoot) {
  final localDir = Directory.fromUri(
      packageRoot.resolve('native/litert_lm/prebuilt/$dirName/'));
  if (_hasMainLib(localDir, dirName)) return localDir;

  final cacheDir = Directory('${_cacheDir().path}/$dirName');
  if (_hasMainLib(cacheDir, dirName)) return cacheDir;

  return null;
}

bool _hasMainLib(Directory dir, String dirName) {
  if (!dir.existsSync()) return false;
  final os = dirName.startsWith('ios') || dirName.startsWith('macos')
      ? 'macos' // dylib
      : dirName.startsWith('windows')
          ? 'windows' // dll
          : 'linux'; // so
  final ext = os == 'macos'
      ? 'dylib'
      : os == 'windows'
          ? 'dll'
          : 'so';
  final prefix = os == 'windows' ? '' : 'lib';
  final fileName = '$prefix$_mainLibName.$ext';
  return File('${dir.path}/$fileName').existsSync();
}

/// Download archive from GitHub Release, verify SHA256, extract to cache.
Future<Directory?> _downloadAndExtract(String dirName) async {
  final archiveName = _archiveName(dirName);
  final expectedChecksum = _checksums[archiveName];
  if (expectedChecksum == null) {
    // No checksum registered — cannot download safely
    return null;
  }

  final cacheBase = _cacheDir();
  final targetDir = Directory('${cacheBase.path}/$dirName');
  final archiveFile = File('${cacheBase.path}/$archiveName');

  try {
    // Create cache directory
    if (!cacheBase.existsSync()) {
      cacheBase.createSync(recursive: true);
    }

    // Download
    final url = '$_releaseBase/$archiveName';
    stderr.writeln('flutter_gemma: Downloading native libs from $url ...');

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

    // Verify SHA256
    final bytes = await archiveFile.readAsBytes();
    final actualChecksum = sha256.convert(bytes).toString();
    if (actualChecksum != expectedChecksum) {
      stderr.writeln('flutter_gemma: Checksum mismatch!');
      stderr.writeln('  Expected: $expectedChecksum');
      stderr.writeln('  Actual:   $actualChecksum');
      archiveFile.deleteSync();
      return null;
    }
    stderr.writeln('flutter_gemma: Checksum verified');

    // Extract
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

    // Clean up archive
    archiveFile.deleteSync();

    stderr.writeln('flutter_gemma: Native libs cached to ${targetDir.path}');
    return targetDir;
  } catch (e) {
    stderr.writeln('flutter_gemma: Download failed: $e');
    if (archiveFile.existsSync()) archiveFile.deleteSync();
    return null;
  }
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    // Supported platforms: desktop + iOS + Android
    // Web uses MediaPipe JS (dart:ffi blocked in WASM)
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
    if (dirName == null) return; // Unsupported arch (e.g. arm32), skip

    // Wipe stale per-platform subdirs if `_nativeVersion` changed since
    // the cache was last populated. Without this, an upgrade leaves old
    // companion libs in place because `_resolveLibDir` finds the main lib
    // and skips the download.
    _invalidateCacheIfStale();

    // Priority: local prebuilt/ → cache → download from GitHub Release
    var libDir = _resolveLibDir(dirName, input.packageRoot);
    if (libDir == null) {
      // Try downloading
      libDir = await _downloadAndExtract(dirName);
      if (libDir == null) return; // No prebuilt available
    }
    final prebuiltDir = libDir.uri;

    final mainFileName = os.dylibFileName(_mainLibName);
    final mainFileUri = prebuiltDir.resolve(mainFileName);
    if (!File.fromUri(mainFileUri).existsSync()) return;

    output.assets.code.add(
      CodeAsset(
        package: _packageName,
        name: 'src/native/$_mainLibName',
        linkMode: DynamicLoadingBundled(),
        file: mainFileUri,
      ),
    );

    // Stream proxy — tiny C lib that copies callback strings to heap
    final proxyFileName = os.dylibFileName('StreamProxy');
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

    // Companion libs (loaded by libLiteRtLm via dlopen at runtime)
    final companions = [
      'GemmaModelConstraintProvider',
      'LiteRtMetalAccelerator', // macOS + iOS GPU (Metal)
      'LiteRtTopKMetalSampler', // macOS + iOS device GPU sampler (Metal)
      'LiteRtGpuAccelerator', // Android GPU
      'LiteRtOpenClAccelerator', // Android OpenCL
      'LiteRtWebGpuAccelerator', // Linux/Windows GPU (WebGPU → Vulkan/DX12)
      'LiteRtTopKOpenClSampler', // Android OpenCL GPU sampler — honors seed
      'LiteRtTopKWebGpuSampler', // Linux/Windows GPU sampler
      'LiteRt', // Linux/Windows core runtime
    ];
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
    final skipCompanions = os == OS.macOS;
    for (final name in companions) {
      if (skipCompanions) continue;
      final fileName = os.dylibFileName(name);
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

    // Windows: LiteRtLm.dll references companion DLLs by their original
    // Google filenames with "lib" prefix (libLiteRt.dll etc.) via PE imports.
    // Native Assets uses no prefix on Windows (LiteRt.dll), so we ship both
    // names from the CI artifact — register the lib-prefixed copies here
    // so the PE loader can resolve imports at LoadLibrary time.
    if (os == OS.windows) {
      const windowsLibPrefixed = [
        'libGemmaModelConstraintProvider',
        'libLiteRt',
        'libLiteRtTopKWebGpuSampler',
        'libLiteRtWebGpuAccelerator',
      ];
      // DirectXShaderCompiler runtime — required for WebGPU/DX12 shader
      // compilation. Without these the GPU delegate fails at runtime when
      // it tries to compile compute shaders for the LLM kernels.
      // Sourced from microsoft/DirectXShaderCompiler GitHub releases.
      const windowsDxc = ['dxil', 'dxcompiler'];
      // Intel NPU dispatch — required for PreferredBackend.npu on
      // LunarLake / PantherLake-class Intel chips. LiteRtDispatch.dll is
      // the entry point; OpenVino runtime + TBB are loaded transitively
      // at dispatch initialization. ~30 MB combined. Absent dispatch on
      // non-Intel hardware just means engine_create returns a dispatch
      // error — model still loads on CPU / GPU.
      const windowsIntelNpu = [
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
      ];
      for (final name in [
        ...windowsLibPrefixed,
        ...windowsDxc,
        ...windowsIntelNpu,
      ]) {
        final fileName = os.dylibFileName(name);
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

    // 0.15.2: TFLite C 0.12.7 tarball download + Native Assets
    // registration removed. Embedding now uses the LiteRT C API via the
    // same libLiteRtLm (Android/iOS/macOS) or libLiteRt (Linux/Windows)
    // we already ship for inference accelerators — no separate native
    // dependency for embeddings.

    output.dependencies.add(prebuiltDir);
  });
}
