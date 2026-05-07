import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';
const _mainLibName = 'LiteRtLm';

/// LiteRT-LM native library version and release info.
///
/// 0.11.0-a is a fresh build from upstream LiteRT-LM v0.11.0 (Multi-Token
/// Prediction support). Same optimization flags as 0.10.2-b: `-c opt
/// --strip=always` (Bazel) + MSVC `/OPT:REF /OPT:ICF` (Windows).
/// Apple: vtool minos 26.2 → 16.0 patch on libGemmaModelConstraintProvider
/// (#245). Android: `-Wl,-z,max-page-size=16384` (Google Play 16KB).
const _nativeVersion = '0.11.0-a';
const _releaseTag = 'native-v$_nativeVersion';
const _releaseBase =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/$_releaseTag';

/// SHA256 checksums for each platform archive.
/// Updated when new native libs are published to GitHub Release.
const _checksums = <String, String>{
  'litertlm-linux_x86_64.tar.gz':
      '181326c1a1a8b6ce92111c957e06484334186624a99db2f950aaeb5538fc1214',
  'litertlm-linux_arm64.tar.gz':
      '2c13727bd8772ec63829eb86977c6df88f26b65b8b4faf7c292622c55acc43c9',
  'litertlm-windows_x86_64.tar.gz':
      'f6966a4687ae826a9d8c5787ea39f5fd3076da23b18ab33813ba13ac7499ba41',
  'litertlm-macos_arm64.tar.gz':
      '961a3b53be35db8b79f827573aa573e09005a2e50f989b3650404a14c5f60e7d',
  'litertlm-ios_arm64.tar.gz':
      'd10d1e55d115ff57fa4eec28b042c984979cbff2e65140a20db67c0709ff5c33',
  'litertlm-ios_sim_arm64.tar.gz':
      'd6a3f4b278b4f6498169ab665d14edbbc64984aeaa08f7c35d4918b20bd82a5e',
  'litertlm-android_arm64.tar.gz':
      '80d29a6781c9044eca669e6d38801ac6af3e98b06f25653156fabf881e042a49',
};

/// TensorFlow Lite C library (used by `lib/desktop/tflite/tflite_bindings.dart`
/// for embedding inference on macOS/Linux/Windows). Lives at our own
/// `v0.12.7` release — built from LiteRT 2.1.3, ABI-compatible with the
/// LiteRT-LM 0.10.2 series. Fetched separately from the LiteRT-LM tarballs
/// so versioning stays independent (no need to rebuild `native-v0.10.2-b`
/// just to bump TFLite C). Restored in 0.14.5 after regression from 0.14.0
/// setup-script removal — see #250 follow-up.
const _tfliteVersion = '0.12.7';
const _tfliteReleaseBase =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/v$_tfliteVersion';

/// Per-platform TFLite C artifact: source filename in v0.12.7 release +
/// SHA256. The local cached file is renamed to the canonical bundle name
/// (`libtensorflowlite_c.{dylib,so}` / `tensorflowlite_c.dll`) so Native
/// Assets can register it under a stable basename — `tflite_bindings.dart`
/// loads it via `DynamicLibrary.open('tensorflowlite_c')`.
const _tfliteAssets = <String, ({String src, String dst, String sha256})>{
  'macos_arm64': (
    src: 'libtensorflowlite_c_darwin_arm64.dylib',
    dst: 'libtensorflowlite_c.dylib',
    sha256: '13bcd426b62a0b8b12fb10b6c540cd30f4c2858dd0ce42c0ed67090eb7a60ed1',
  ),
  'linux_x86_64': (
    src: 'libtensorflowlite_c_linux_amd64.so',
    dst: 'libtensorflowlite_c.so',
    sha256: 'f98dcaa2f8033794725413542625a396744928dc5c0a6fd90ff3c0c5b1209327',
  ),
  'linux_arm64': (
    src: 'libtensorflowlite_c_linux_arm64.so',
    dst: 'libtensorflowlite_c.so',
    sha256: '602a0aea312d36697adc042058b3231875b84b7679461214450030f6eace0999',
  ),
  'windows_x86_64': (
    src: 'tensorflowlite_c_windows_amd64.dll',
    dst: 'tensorflowlite_c.dll',
    sha256: 'e185a3170109a33e3b29fe64beeff9eaa162fa1f9dc47a618fa708e21d458bcf',
  ),
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

/// Platform-appropriate cache directory.
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

/// Download a single file (no archive), verify SHA256, place at [dest].
/// Used for TFLite C library prebuilts which are shipped as bare .dll/.so/
/// .dylib files in the v0.12.7 release.
Future<File?> _downloadFile({
  required String url,
  required File dest,
  required String expectedSha256,
}) async {
  // Skip if already cached and checksum matches.
  if (dest.existsSync()) {
    final cached = sha256.convert(await dest.readAsBytes()).toString();
    if (cached == expectedSha256) return dest;
    dest.deleteSync();
  }

  final destDir = dest.parent;
  if (!destDir.existsSync()) destDir.createSync(recursive: true);

  // Download to a `.partial` sibling first, then atomically rename. This
  // keeps Native Assets' "File modified during build" guard happy:
  // [dest] only appears (and stops being modified) once the bytes are
  // fully on disk, instead of growing during the build pass.
  final partial = File('${dest.path}.partial');
  if (partial.existsSync()) partial.deleteSync();

  stderr.writeln('flutter_gemma: Downloading $url ...');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      stderr.writeln(
          'flutter_gemma: TFLite C download failed (HTTP ${response.statusCode})');
      return null;
    }
    final sink = partial.openWrite();
    await response.pipe(sink);
  } finally {
    client.close();
  }

  final actual = sha256.convert(await partial.readAsBytes()).toString();
  if (actual != expectedSha256) {
    stderr.writeln('flutter_gemma: TFLite C checksum mismatch!');
    stderr.writeln('  Expected: $expectedSha256');
    stderr.writeln('  Actual:   $actual');
    partial.deleteSync();
    return null;
  }

  partial.renameSync(dest.path);
  stderr.writeln('flutter_gemma: TFLite C cached to ${dest.path}');
  return dest;
}

/// Resolve the local TFLite C library file for [dirName], downloading from
/// the v0.12.7 release into the same cache layout used by LiteRT-LM libs
/// if not already present. Returns null on unsupported platforms (iOS /
/// Android / web — they don't use TFLite C via FFI).
Future<File?> _resolveTfliteLib(String dirName) async {
  final asset = _tfliteAssets[dirName];
  if (asset == null) return null;

  // Mirror LiteRT-LM `_resolveLibDir` order: in-repo prebuilt → cache → fetch.
  final cacheBase = _cacheDir();
  final platformDir = Directory('${cacheBase.path}/$dirName');
  final cached = File('${platformDir.path}/${asset.dst}');
  if (cached.existsSync()) {
    final hash = sha256.convert(await cached.readAsBytes()).toString();
    if (hash == asset.sha256) return cached;
  }

  return _downloadFile(
    url: '$_tfliteReleaseBase/${asset.src}',
    dest: cached,
    expectedSha256: asset.sha256,
  );
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
      for (final name in [...windowsLibPrefixed, ...windowsDxc]) {
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

    // TFLite C library — desktop embeddings only (`lib/desktop/tflite/`).
    // Skipped on iOS / Android / web. Bundled as `tensorflowlite_c` so
    // `DynamicLibrary.open('tensorflowlite_c')` in tflite_bindings.dart
    // resolves through Native Assets on each desktop OS. Restored in
    // 0.14.5 after regression from setup-script removal in 0.14.0
    // (#250 follow-up: Erik xErik report on Windows).
    if (os == OS.macOS || os == OS.linux || os == OS.windows) {
      final tfliteFile = await _resolveTfliteLib(dirName);
      if (tfliteFile != null) {
        output.assets.code.add(
          CodeAsset(
            package: _packageName,
            name: 'src/native/tensorflowlite_c',
            linkMode: DynamicLoadingBundled(),
            file: tfliteFile.uri,
          ),
        );
      }
    }

    output.dependencies.add(prebuiltDir);
  });
}
