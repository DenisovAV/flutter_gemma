import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';
const _mainLibName = 'LiteRtLm';

/// LiteRT-LM native library version and release info.
///
/// 0.10.2-a is a re-release of 0.10.2 with three patched tarballs:
///   - android_arm64: libLiteRtLm.so rebuilt with -Wl,-z,max-page-size=16384
///     (Google Play 16KB page-size requirement, #253)
///   - ios_arm64 / ios_sim_arm64: libGemmaModelConstraintProvider.dylib
///     LC_BUILD_VERSION minos lowered 26.2 → 14.0 via vtool to fix
///     App Store Connect ITMS-90208 rejection (#245).
/// Linux / macOS / Windows tarballs are byte-identical to 0.10.2.
const _nativeVersion = '0.10.2-a';
const _releaseTag = 'native-v$_nativeVersion';
const _releaseBase =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/$_releaseTag';

/// SHA256 checksums for each platform archive.
/// Updated when new native libs are published to GitHub Release.
const _checksums = <String, String>{
  'litertlm-linux_x86_64.tar.gz':
      'ddeebb24ac8df974abbb7072ade0f170e5199dfb3b4f53ebf435d10671549840',
  'litertlm-linux_arm64.tar.gz':
      '87b703ca9387985e0e945d096c290233946b17b5cf601dfdc70c9e82dd172e21',
  'litertlm-windows_x86_64.tar.gz':
      'cb7a742ba537f722e294e62c55b4de720e5a96ff1f1e2933ba7a20a96aecc7b6',
  'litertlm-macos_arm64.tar.gz':
      '2f4a7d5b37b2a16c89b5ab305c55900c5b47e796273422f2d922c4f52d21716d',
  'litertlm-ios_arm64.tar.gz':
      '15c1c11ae92e59e0c7fde888e703d5b2dcaca5bf98f2fc1c11a47f3b8fb09728',
  'litertlm-ios_sim_arm64.tar.gz':
      'bd9f8be9b84d77f0a7231eac8f5d2155eb0a2f0c76050d7be79b79a302da3a26',
  'litertlm-android_arm64.tar.gz':
      'd856f78c2ea7c48f7116ff2cecf76ba7cd9d3935321d54c48d0ff998e48d86c6',
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

    output.dependencies.add(prebuiltDir);
  });
}
