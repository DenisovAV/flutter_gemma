import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma';
const _mainLibName = 'LiteRtLm';

/// LiteRT-LM native library version and release info.
const _nativeVersion = '0.10.2';
const _releaseTag = 'native-v$_nativeVersion';
const _releaseBase =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/$_releaseTag';

/// SHA256 checksums for each platform archive.
/// Updated when new native libs are published to GitHub Release.
const _checksums = <String, String>{
  'litertlm-linux_x86_64.tar.gz':
      'a854bcefe86977a33a54975b836943e200a54dbf590644a669db9d1a4553da92',
  'litertlm-linux_arm64.tar.gz':
      '276c5aeff5efc84203ade0fe60f30460382fd742e55bcc072a4927715f93facb',
  'litertlm-windows_x86_64.tar.gz':
      '55e30057b2fbd80c16c04dd4294db14c3fb23349eab353eecc4966a0d7499ee6',
  'litertlm-macos_arm64.tar.gz':
      '9f643ac50aeffa3b12a8b120189132c99b2784c73b19f905a5cbf0e5ac366da0',
  'litertlm-ios_arm64.tar.gz':
      '4b60f558098174795042015c1cee3bff5194d1043eceae591580f6a0a5369eca',
  'litertlm-ios_sim_arm64.tar.gz':
      'ad59c07e4bbc0c3494252e0207047c2af55ee0ea674d312d5225a1d28bb58dea',
  'litertlm-android_arm64.tar.gz':
      'f8d24a050d6ede531c173b99d265a0890d6b08d536b4340dfa0147e62c99172d',
};

/// Resolve prebuilt directory name for the given OS + architecture.
/// iOS distinguishes device vs simulator via IOSSdk.
String? _prebuiltDirName(OS os, Architecture arch, {IOSSdk? iOSSdk}) {
  if (os == OS.iOS) {
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
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
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
  final localDir =
      Directory.fromUri(packageRoot.resolve('native/litert_lm/prebuilt/$dirName/'));
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
  final ext = os == 'macos' ? 'dylib' : os == 'windows' ? 'dll' : 'so';
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
        stderr.writeln('flutter_gemma: Download failed (HTTP ${response.statusCode})');
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
      'LiteRtMetalAccelerator', // macOS GPU
      'LiteRtGpuAccelerator', // Android GPU
      'LiteRtOpenClAccelerator', // Android OpenCL
    ];
    for (final name in companions) {
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

    output.dependencies.add(prebuiltDir);
  });
}
