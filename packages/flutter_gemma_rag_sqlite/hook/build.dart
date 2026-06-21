// Native Assets hook for flutter_gemma_rag_sqlite.
//
// Fetches the per-platform `sqlite-vec` (`vec0`) loadable extension from the
// asg017/sqlite-vec GitHub Release, SHA256-verifies it, and registers it as a
// CodeAsset so the bundled `vec0` library is resolvable at runtime via
// `DynamicLibrary.open` (see SqliteVectorStore._resolveVec0Path).
//
// Modeled on flutter_gemma_rag_qdrant/hook/build.dart, but the upstream
// loadable tarballs ship a BARE `vec0.so`/`vec0.dylib`/`vec0.dll` (no `lib`
// prefix). To keep the runtime loader path uniform with qdrant/litert
// (`libvec0.so` on Unix-like, `vec0.framework/vec0` on Apple, `vec0.dll` on
// Windows), we normalize the extracted file's name before registering it.
//
// The hook only needs to COMPILE and resolve on the host build machine; real
// per-platform runtime loading is verified manually after a native build.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma_rag_sqlite';

/// sqlite-vec loadable-extension release on asg017/sqlite-vec.
const _vecVersion = '0.1.9';
const _releaseBase =
    'https://github.com/asg017/sqlite-vec/releases/download/v$_vecVersion';

/// Logical CodeAsset name (the runtime resolves the bundled file by its
/// filename; this is just the asset identity inside the package).
const _assetName = 'src/native/vec0';

/// Per-platform upstream archive name suffix. Full archive name is
/// `sqlite-vec-$_vecVersion-loadable-<suffix>.tar.gz`. Keyed by the prebuilt
/// directory name resolved from (OS, arch, iOS sdk).
const Map<String, String> _archiveSuffix = {
  'android_arm64': 'android-aarch64',
  'ios_arm64': 'ios-aarch64',
  'ios_sim_arm64': 'iossimulator-aarch64',
  'linux_x86_64': 'linux-x86_64',
  'linux_arm64': 'linux-aarch64',
  'macos_arm64': 'macos-aarch64',
  'windows_x86_64': 'windows-x86_64',
};

/// SHA256 of each upstream archive, keyed by the prebuilt directory name.
const Map<String, String> _checksums = {
  'android_arm64':
      '76f60d4d2d89d2e5070ef8f1868c52b140a10200dbe98b0c2ca7a4d02d483eaa',
  'ios_arm64':
      '3cb77b829cc42fe0544608790e19d87efd61076639bd8b78d68f4fefb8fb8561',
  'ios_sim_arm64':
      '7db1a8077ac496b79bb0a386ab6bfa5bd507cb45c9431ab644c69bf17f597070',
  'linux_x86_64':
      'b959baa1d8dc88861b1edb337b8587178cdcb12d60b4998f9d10b6a82052d5d7',
  'linux_arm64':
      'ea03d39541e478fab5974253c461e1cb5d77742f69e40cf96e3fad5bc309a37c',
  'macos_arm64':
      '8282126333399ddfe98bbbcc7a1936e7252625aac49df056a98be602e46bfd29',
  'windows_x86_64':
      '51581189d52066b4dfc6631f6d7a3eab7dedc2260656ab09ca97ab3fb8165983',
};

// ============================================================================
// Per-platform name resolution
// ============================================================================

/// Resolve the prebuilt directory name for (OS, arch, iOS sdk). iOS
/// distinguishes device vs simulator via IOSSdk.
String? _prebuiltDirName(OS os, Architecture arch, {IOSSdk? iOSSdk}) {
  if (os == OS.iOS) {
    if (arch != Architecture.arm64) return null; // arm64 only
    return iOSSdk == IOSSdk.iPhoneSimulator ? 'ios_sim_arm64' : 'ios_arm64';
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

/// Bundled filename the runtime loader expects, keeping parity with the
/// qdrant/litert convention: `lib<name>.so` on Unix-like, `<name>.dylib` on
/// Apple, `<name>.dll` on Windows. (Upstream ships a bare `vec0.<ext>` inside
/// each tarball — see [_upstreamFileName].)
String _bundledFileName(OS os) => switch (os) {
  OS.windows => 'vec0.dll',
  OS.macOS || OS.iOS => 'libvec0.dylib',
  _ => 'libvec0.so',
};

/// Name of the loadable inside the upstream tarball (no `lib` prefix).
String _upstreamFileName(OS os) => switch (os) {
  OS.windows => 'vec0.dll',
  OS.macOS || OS.iOS => 'vec0.dylib',
  _ => 'vec0.so',
};

// ============================================================================
// Cache layout
// ============================================================================

/// Platform-appropriate base cache directory. The vec0 loadables live under a
/// `sqlite_vec/` namespace so they never collide with the litert/qdrant caches.
Directory _cacheRoot() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final Directory base;
  if (Platform.isWindows) {
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
    base = Directory('$localAppData\\flutter_gemma\\native');
  } else if (Platform.isMacOS) {
    base = Directory('$home/Library/Caches/flutter_gemma/native');
  } else {
    base = Directory('$home/.cache/flutter_gemma/native');
  }
  return Directory('${base.path}/sqlite_vec/$_vecVersion');
}

// ============================================================================
// Resolve / download + verify + extract
// ============================================================================

/// Returns the directory containing the normalized bundled file for [dirName],
/// fetching + verifying + extracting the upstream tarball if it isn't cached.
/// Returns null on any failure (unsupported target, download/checksum/extract
/// error) — the build proceeds without the CodeAsset and runtime fails with a
/// clear dlopen error at first use.
Future<Directory?> _resolveLibDir(OS os, String dirName) async {
  final expectedChecksum = _checksums[dirName];
  final suffix = _archiveSuffix[dirName];
  if (expectedChecksum == null || suffix == null) return null;

  final cacheRoot = _cacheRoot();
  final targetDir = Directory('${cacheRoot.path}/$dirName');
  final bundledName = _bundledFileName(os);

  // Already cached + normalized.
  if (File('${targetDir.path}/$bundledName').existsSync()) return targetDir;

  final archiveName = 'sqlite-vec-$_vecVersion-loadable-$suffix.tar.gz';
  final archiveFile = File('${cacheRoot.path}/$archiveName');

  try {
    if (!cacheRoot.existsSync()) cacheRoot.createSync(recursive: true);

    final url = '$_releaseBase/$archiveName';
    stderr.writeln(
      'flutter_gemma: Downloading sqlite-vec ($dirName) from $url',
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln(
          'flutter_gemma: sqlite-vec download failed (HTTP ${response.statusCode})',
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
      stderr.writeln(
        'flutter_gemma: sqlite-vec checksum mismatch for $archiveName!',
      );
      stderr.writeln('  Expected: $expectedChecksum');
      stderr.writeln('  Actual:   $actualChecksum');
      archiveFile.deleteSync();
      return null;
    }
    stderr.writeln(
      'flutter_gemma: sqlite-vec checksum verified ($archiveName)',
    );

    // Extract into a sibling temp dir on the SAME filesystem, normalize the
    // upstream `vec0.<ext>` to the bundled name, then atomically rename into
    // place. A torn extract leaves only the temp dir (cleaned in finally).
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
          'flutter_gemma: sqlite-vec extract failed: ${result.stderr}',
        );
        return null;
      }
      // Normalize: upstream ships a bare `vec0.<ext>`; rename to the bundled
      // filename the runtime loader resolves.
      final extracted = File('${tmpDir.path}/${_upstreamFileName(os)}');
      if (!extracted.existsSync()) {
        stderr.writeln(
          'flutter_gemma: sqlite-vec tarball missing ${_upstreamFileName(os)}',
        );
        return null;
      }
      if (_upstreamFileName(os) != bundledName) {
        extracted.renameSync('${tmpDir.path}/$bundledName');
      }
      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      tmpDir.renameSync(targetDir.path); // atomic on same FS
    } finally {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    }
    archiveFile.deleteSync();
    stderr.writeln('flutter_gemma: sqlite-vec cached to ${targetDir.path}');
    return targetDir;
  } catch (e) {
    stderr.writeln('flutter_gemma: sqlite-vec download failed: $e');
    if (archiveFile.existsSync()) archiveFile.deleteSync();
    return null;
  }
}

// ============================================================================
// Entry point
// ============================================================================

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    // Native platforms only — web uses wa-sqlite (dart:ffi blocked in WASM).
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
    if (dirName == null) return; // unsupported arch — skip

    final libDir = await _resolveLibDir(os, dirName);
    if (libDir == null) return;

    final bundledName = _bundledFileName(os);
    final fileUri = libDir.uri.resolve(bundledName);
    if (!File.fromUri(fileUri).existsSync()) return;

    // APPLE-ONLY staging (Xcode "Cycle inside Flutter Assemble"): copy the
    // dylib into the hook's outputDirectory so the registered output asset does
    // not live inside the cache dependency dir. Windows/Linux register straight
    // from the cache. Mirrors the litert/qdrant hooks.
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
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: stage(fileUri),
      ),
    );
    output.dependencies.add(libDir.uri);
  });
}
