// Native Assets hook for flutter_gemma_rag_sqlite.
//
// Registers the per-platform `sqlite-vec` (`vec0`) loadable extension as a
// CodeAsset so the bundled library is resolvable at runtime via
// `DynamicLibrary.open` (see SqliteVectorStore._resolveVec0Path).
//
// The loadables are FETCHED from a versioned GitHub Release, the same shape
// `flutter_gemma_litertlm` uses. They used to be committed into the package
// under `native/sqlite_vec/prebuilt/` and read locally, on the reasoning that
// ~1 MB was too small to be worth a download. That was wrong twice over:
//
//   * every consumer received all seven targets — 1.2 MB of the 3.4 MB
//     unpacked package — to use exactly one of them;
//   * the local path carries no version, so it is the same path across an
//     upgrade. The build cache hashes a DIRECTORY as its sorted child NAMES
//     (`_hashDirectory` in package:native_assets_builder — no content, no
//     mtime), and `stage()` compared file LENGTHS, so a rebuilt library that
//     kept its name and size was invisible end to end. That is not theory:
//     re-stamping `ios_arm64/libvec0.dylib` from LC_VERSION_MIN_IPHONEOS to
//     LC_BUILD_VERSION consumed 8 bytes of Mach-O header slack, so the device
//     slice went 158440 -> 158440 and the corrected binary never reached an
//     incremental build.
//
// A version-keyed cache path removes that class of bug structurally rather
// than by guarding against it: a new bundle version is a new directory, so
// there is nothing stale to mistake for current.
//
// Local prebuilts still win when present (`native/sqlite_vec/prebuilt/<target>/`)
// — that is the maintainer path, so `build_local.sh` output can be tested
// before it is ever released. They are gitignored and `.pubignore`d; consumers
// only ever see the download path.
//
// The android `.so` is OUR rebuild from the amalgamation with 16 KB ELF
// LOAD-segment alignment (`-Wl,-z,max-page-size=16384`) for Android 15 / Play
// targetSdk 35+ (#319); the rest are asg017 upstream loadables. Regenerate
// them all with `native/sqlite_vec/build_local.sh`, then follow the release
// steps in that script's header.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma_rag_sqlite';

/// Logical CodeAsset name (the runtime resolves the bundled file by its
/// filename; this is just the asset identity inside the package).
const _assetName = 'src/native/vec0';

/// Bundle version — the upstream `sqlite-vec` release these bytes come from.
///
/// Same convention as the `native-v*` tags this repo already uses for LiteRT-LM
/// (`native-v0.16.0` carries upstream v0.16.0), including how it handles the
/// case the number alone cannot express: a REBUILD of an unchanged upstream
/// takes a letter suffix — `native-v0.12.0-a`, `-b`, `native-v0.13.1-a`.
///
/// Use that suffix whenever the shipped bytes change without the upstream
/// moving: the 16 KB-alignment android rebuild, an Apple `vtool` re-stamp, a
/// different sqlite amalgamation. What must never happen is reusing a version
/// for different bytes — the cache path is keyed on this string, so the
/// previous release's files simply stay, and the build links against libraries
/// it was never pinned to.
const _bundleVersion = '0.1.9';

const _releaseTag = 'native-sqlite-vec-v$_bundleVersion';
const _markerFileName = '.flutter_gemma_sqlite_vec_version';
const _releaseBase =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/$_releaseTag';

/// SHA256 of each published archive.
///
/// A registered checksum is a PROMISE that the platform is supported: if the
/// archive then fails to arrive or fails to verify, that is a broken build and
/// the hook throws. A target absent from this map is one we ship nothing for
/// on purpose — the build proceeds without the CodeAsset.
///
/// These sums must equal both the bytes GitHub serves and the
/// `checksums_sqlite_vec.txt` published alongside them on the release. A stale
/// txt sent a user down the wrong path while debugging a mismatch (#316).
const Map<String, String> _checksums = {
  'sqlite-vec-android_arm64.tar.gz':
      'c9bbff1b96af70d95c1b72feb22e8e14c1e992371f0422487693fb301c58c71b',
  'sqlite-vec-ios_arm64.tar.gz':
      '1d78726208dd730fb0cb600720a3fc8162a3be44505b88f167b1ec62e948fb62',
  'sqlite-vec-ios_sim_arm64.tar.gz':
      '5a156be144658f96a84cb9e5d74485e5a8934795e9f8875dea2e55e9a3d5abca',
  'sqlite-vec-linux_arm64.tar.gz':
      'a1d440391722a51b265ff20d911fa2eca930248596acc54d1b5030428b6eda92',
  'sqlite-vec-linux_x86_64.tar.gz':
      '45f10babcc5f771b5600913ecc57cafec6c943f60cb4c74ca29b15f8e9cbf18c',
  'sqlite-vec-macos_arm64.tar.gz':
      'd27399725b74b8ecf35de42bfc10b909cff4c9318786b85476ab7a5e7b5e6cc3',
  'sqlite-vec-windows_x86_64.tar.gz':
      'b9817ea1d734778dfbfdc1df8253ebcfb89bac3106b3b0e6cd99937a7ba6df86',
};

String _archiveName(String dirName) => 'sqlite-vec-$dirName.tar.gz';

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
/// litert convention: `lib<name>.so` on Unix-like, `lib<name>.dylib` on Apple,
/// `<name>.dll` on Windows. The published archives use this exact name (see
/// `native/sqlite_vec/build_local.sh`).
String _bundledFileName(OS os) => switch (os) {
  OS.windows => 'vec0.dll',
  OS.macOS || OS.iOS => 'libvec0.dylib',
  _ => 'libvec0.so',
};

// ============================================================================
// Cache
// ============================================================================

/// Cache root for downloaded archives: `<base>/sqlite_vec`.
///
/// NAMESPACED but not versioned, matching `onnx_genai/` and `qdrant_edge/`
/// already on disk. Staleness is handled by [_markerFile] plus an explicit
/// wipe, which is this repo's convention and what
/// `hostNativeLibraryCandidates(cacheNamespace:)` — the shared locator the
/// host-side tests use — knows how to find. Putting the version in the path
/// instead works, but only the hook would know the layout: the locator would
/// look under `sqlite_vec/<target>/`, find nothing, and every store suite would
/// skip itself.
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
  return Directory('${base.path}${Platform.pathSeparator}sqlite_vec');
}

/// Records which bundle version populated [_cacheRoot].
File _markerFile() =>
    File('${_cacheRoot().path}${Platform.pathSeparator}$_markerFileName');

/// Drops cached libraries left by a DIFFERENT bundle version.
///
/// Without this the cache path — which carries no version — would keep serving
/// the previous release's files forever: the archive is only downloaded when
/// the library is absent, so a version bump alone would never be noticed. Same
/// mechanism as `_invalidateBundleCacheIfStale` in the litertlm hook.
void _invalidateCacheIfStale() {
  final marker = _markerFile();
  final cached = marker.existsSync() ? marker.readAsStringSync().trim() : null;
  if (cached == _bundleVersion) return;

  final root = _cacheRoot();
  if (root.existsSync()) {
    for (final entry in root.listSync()) {
      if (entry is Directory) entry.deleteSync(recursive: true);
    }
    if (cached != null) {
      stderr.writeln(
        'flutter_gemma_rag_sqlite: dropped cached sqlite-vec $cached '
        '(now pinned to $_bundleVersion)',
      );
    }
  }
  if (marker.existsSync()) marker.deleteSync();
}

bool _hasLib(Directory dir, OS os) => File(
  '${dir.path}${Platform.pathSeparator}${_bundledFileName(os)}',
).existsSync();

/// Local prebuilt first (the maintainer path — `build_local.sh` output is
/// testable before it is released), then the download cache.
Directory? _resolveLibDir(String dirName, Uri packageRoot, OS os) {
  final localDir = Directory.fromUri(
    packageRoot.resolve('native/sqlite_vec/prebuilt/$dirName/'),
  );
  if (_hasLib(localDir, os)) return localDir;

  final cacheDir = Directory('${_cacheRoot().path}/$dirName');
  if (_hasLib(cacheDir, os)) return cacheDir;

  return null;
}

// ============================================================================
// Download + verify + extract
// ============================================================================

Future<Directory?> _downloadAndExtract(String dirName, OS os) async {
  final archiveName = _archiveName(dirName);
  final expectedChecksum = _checksums[archiveName];
  if (expectedChecksum == null) {
    // No checksum registered — the ONLY legitimate reason this returns null.
    // The build proceeds without the CodeAsset and the runtime fails at first
    // use with a clear dlopen error. Every other failure below THROWS: a
    // registered checksum promises the platform is supported, so failing to
    // produce the library is a broken build, not a skip — and a hook that
    // returns null there reports success, ships an app with no native library,
    // and surfaces as an opaque crash on the user's device (#316's shape).
    return null;
  }

  final cacheRoot = _cacheRoot();
  final targetDir = Directory('${cacheRoot.path}/$dirName');
  final archiveFile = File('${cacheRoot.path}/$archiveName');

  try {
    if (!cacheRoot.existsSync()) cacheRoot.createSync(recursive: true);

    final url = '$_releaseBase/$archiveName';
    stderr.writeln(
      'flutter_gemma_rag_sqlite: downloading sqlite-vec $_bundleVersion '
      'for $dirName from $url ...',
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError(
          'flutter_gemma_rag_sqlite: could not download sqlite-vec for '
          '$dirName — HTTP ${response.statusCode} from $url.\n'
          'This platform HAS a registered checksum, so the archive is expected '
          'to exist. Check network access to github.com, or that release tag '
          '"$_releaseTag" still carries $archiveName.',
        );
      }
      final sink = archiveFile.openWrite();
      await response.pipe(sink);
    } finally {
      client.close();
    }

    final bytes = await archiveFile.readAsBytes();
    final actualChecksum = sha256.convert(bytes).toString();
    if (actualChecksum != expectedChecksum) {
      archiveFile.deleteSync();
      // An integrity failure has no benign reading, so this is the one case
      // that must never degrade to "build succeeded". It means the bytes
      // GitHub served are not the bytes this package version was built against
      // — a re-uploaded tag (#316), a corrupted transfer, or a MITM.
      throw StateError(
        'flutter_gemma_rag_sqlite: CHECKSUM MISMATCH for $archiveName.\n'
        '  expected $expectedChecksum\n'
        '  actual   $actualChecksum\n'
        'The archive served by $_releaseBase does not match what sqlite-vec '
        '$_bundleVersion was pinned to. Re-run to rule out a corrupt transfer; '
        'if it persists, the release asset was replaced after publication and '
        'the pin can no longer be satisfied — do NOT work around it by '
        'clearing the checksum.',
      );
    }

    // Extract into a sibling temp dir on the SAME filesystem, then rename into
    // place. A torn extract leaves only the temp dir, never a half-populated
    // targetDir that the next run would mistake for a complete one.
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
        throw StateError(
          'flutter_gemma_rag_sqlite: failed to extract $archiveName '
          '(tar exit ${result.exitCode}): ${result.stderr}',
        );
      }
      if (!_hasLib(tmpDir, os)) {
        throw StateError(
          'flutter_gemma_rag_sqlite: $archiveName extracted but '
          '${_bundledFileName(os)} is not in it. The archive on $_releaseTag '
          'is not the one this hook expects.',
        );
      }
      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      tmpDir.renameSync(targetDir.path);
    } finally {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    }

    archiveFile.deleteSync();
    _markerFile().writeAsStringSync(_bundleVersion);
    stderr.writeln(
      'flutter_gemma_rag_sqlite: sqlite-vec $dirName ready (checksum verified)',
    );
    return targetDir;
  } on StateError {
    rethrow;
  } catch (e) {
    throw StateError(
      'flutter_gemma_rag_sqlite: could not prepare sqlite-vec for $dirName: $e',
    );
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

    // Native platforms only — web uses the custom vec0 wasm (dart:ffi is
    // blocked in WASM).
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
    if (dirName == null) {
      return; // unsupported target — runtime fails with a clear dlopen error
    }

    _invalidateCacheIfStale();

    var libDir = _resolveLibDir(dirName, input.packageRoot, os);
    libDir ??= await _downloadAndExtract(dirName, os);
    if (libDir == null) return; // nothing registered for this target

    final srcUri = libDir.uri.resolve(_bundledFileName(os));

    // APPLE-ONLY staging (Xcode "Cycle inside Flutter Assemble"): copy the
    // dylib into the hook's outputDirectory so the registered output asset
    // does not live inside the directory we also declare as an input.
    // Windows/Linux register straight from the resolved dir. Mirrors the
    // litertlm hook, including the reason staging stops at Apple.
    Uri stage(Uri uri) {
      if (os != OS.macOS && os != OS.iOS) return uri;
      final src = File.fromUri(uri);
      final destUri = input.outputDirectory.resolve(uri.pathSegments.last);
      final dest = File.fromUri(destUri);
      // Compare CONTENT, not length: the staged directory is named after the
      // build CONFIG alone, so it is reused across an upgrade and across a
      // local rebuild, and a size-only guard keeps the previous binary
      // whenever the replacement happens to be the same size.
      if (!dest.existsSync() || !_sameBytes(src, dest)) {
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
        file: stage(srcUri),
      ),
    );
    // The FILE, not its directory: a directory dependency is hashed as the
    // sorted list of child names only, so it cannot see a library change.
    output.dependencies.add(srcUri);
  });
}

/// Byte-for-byte comparison of two existing files.
///
/// `stage()` compares CONTENT rather than `lengthSync()`. The staged directory
/// is named after the build CONFIG alone — no package version, no package root
/// — so the same path is reused across an upgrade and across a local native
/// rebuild. A size-only guard therefore keeps the previous binary whenever the
/// replacement happens to be the same size, which is exactly what re-stamping
/// a Mach-O load command produces.
///
/// Byte-identical in `flutter_gemma_litertlm` and `flutter_gemma_onnx`; the
/// packages publish independently and cannot share it.
bool _sameBytes(File a, File b) {
  if (a.lengthSync() != b.lengthSync()) return false;
  final x = a.readAsBytesSync();
  final y = b.readAsBytesSync();
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
