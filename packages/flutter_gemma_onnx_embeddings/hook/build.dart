import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_gemma_onnx_embeddings/src/ort_hook_constants.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma_onnx_embeddings';

// Public testable constants (kOnnxOrtNamespace, kOnnxOrtMainLibName,
// kOnnxOrtChecksums) are defined in lib/src/ort_hook_constants.dart and
// re-exported from there so tests can import them without triggering the
// native-assets build pipeline.

// ============================================================================
// Per-platform archive config
// ============================================================================

/// Version-per-source-channel. Different channels lag at different rates.
const _linuxVersion = '1.27.0';
const _macosVersion = '1.27.0';
const _windowsArm64Version = '1.27.0';
const _windowsX64Version = '1.26.0'; // CPU zip absent in 1.27.0
const _androidVersion = '1.26.0'; // Maven lags; 1.27.0 not yet on Maven Central

/// Per-platform download URL resolver. Each platform may come from a different
/// Microsoft channel (GitHub releases, Maven Central, CocoaPods CDN).
///
/// Returns null for unsupported or BLOCKED platforms (iOS static, macOS x64).
String? _downloadUrl(String dirName) {
  return switch (dirName) {
    'linux_x86_64' =>
      'https://github.com/microsoft/onnxruntime/releases/download/'
          'v$_linuxVersion/onnxruntime-linux-x64-$_linuxVersion.tgz',
    'linux_arm64' =>
      'https://github.com/microsoft/onnxruntime/releases/download/'
          'v$_linuxVersion/onnxruntime-linux-aarch64-$_linuxVersion.tgz',
    'macos_arm64' =>
      'https://github.com/microsoft/onnxruntime/releases/download/'
          'v$_macosVersion/onnxruntime-osx-arm64-$_macosVersion.tgz',
    // macos_x86_64 → null (BLOCKED — no standalone tarball in 1.27.0+)
    'windows_x86_64' =>
      'https://github.com/microsoft/onnxruntime/releases/download/'
          'v$_windowsX64Version/onnxruntime-win-x64-$_windowsX64Version.zip',
    'windows_arm64' =>
      'https://github.com/microsoft/onnxruntime/releases/download/'
          'v$_windowsArm64Version/onnxruntime-win-arm64-$_windowsArm64Version.zip',
    'android_arm64' =>
      'https://repo1.maven.org/maven2/com/microsoft/onnxruntime/'
          'onnxruntime-android/$_androidVersion/'
          'onnxruntime-android-$_androidVersion.aar',
    // ios_arm64, ios_sim_arm64 → null (BLOCKED — static framework only;
    // CocoaPods path via flutter_onnxruntime dep instead)
    _ => null,
  };
}

/// Archive filename for [dirName], used as the checksum map key.
String? _archiveName(String dirName) {
  return switch (dirName) {
    'linux_x86_64' => 'onnxruntime-linux-x64-$_linuxVersion.tgz',
    'linux_arm64' => 'onnxruntime-linux-aarch64-$_linuxVersion.tgz',
    'macos_arm64' => 'onnxruntime-osx-arm64-$_macosVersion.tgz',
    'windows_x86_64' => 'onnxruntime-win-x64-$_windowsX64Version.zip',
    'windows_arm64' => 'onnxruntime-win-arm64-$_windowsArm64Version.zip',
    'android_arm64' => 'onnxruntime-android-$_androidVersion.aar',
    _ => null,
  };
}

/// Companion libraries needed on each platform for the ONNX Runtime CPU EP.
///
/// Linux + Windows: `onnxruntime_providers_shared` is a required runtime DLL/SO
/// (CPU Execution Provider shared state). Absent → ONNX model load fails with
/// "libonnxruntime_providers_shared.so: cannot open shared object file".
///
/// macOS / Android / iOS: no companion needed for the plain CPU EP.
List<String> _companions(String dirName) {
  return switch (dirName) {
    'linux_x86_64' || 'linux_arm64' => ['onnxruntime_providers_shared'],
    'windows_x86_64' || 'windows_arm64' => ['onnxruntime_providers_shared'],
    _ => const [],
  };
}

// ============================================================================
// Cache layout
// ============================================================================

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

Directory _cacheRootForOrt() =>
    Directory('${_cacheBaseDir().path}/$kOnnxOrtNamespace');

File _markerFile() => File('${_cacheRootForOrt().path}/.version');

/// Current cached version identifier (encodes all relevant version strings so a
/// version bump on any channel triggers a refetch).
String get _markerVersion =>
    'linux=$_linuxVersion,macos=$_macosVersion,win_x64=$_windowsX64Version,'
    'win_arm64=$_windowsArm64Version,android=$_androidVersion';

({String version, String owner})? _readMarker() {
  final f = _markerFile();
  if (!f.existsSync()) return null;
  try {
    final decoded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final v = decoded['version'];
    final o = decoded['owner'];
    if (v is String && o is String) return (version: v, owner: o);
    return null;
  } catch (_) {
    return null;
  }
}

void _writeMarker() {
  _markerFile().writeAsStringSync(
    jsonEncode({'version': _markerVersion, 'owner': _packageName}),
  );
}

void _invalidateCacheIfStale() {
  final cacheRoot = _cacheRootForOrt();
  if (!cacheRoot.existsSync()) {
    cacheRoot.createSync(recursive: true);
    return;
  }
  final stored = _readMarker();
  if (stored != null && stored.version == _markerVersion) return;

  // Version changed (or marker missing/corrupt) — wipe all platform subdirs.
  final platformPattern = RegExp(r'^(linux|macos|ios|android|windows)_');
  for (final entity in cacheRoot.listSync()) {
    if (entity is! Directory) continue;
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (platformPattern.hasMatch(name)) {
      entity.deleteSync(recursive: true);
    }
  }
}

// ============================================================================
// Dynamic-library file naming
// ============================================================================

String _dylibFileName(OS os, String name) {
  return switch (os) {
    OS.windows => '$name.dll',
    OS.macOS || OS.iOS => 'lib$name.dylib',
    _ => 'lib$name.so',
  };
}

bool _hasMainLib(Directory dir, OS os) {
  if (!dir.existsSync()) return false;
  return File('${dir.path}/${_dylibFileName(os, kOnnxOrtMainLibName)}')
      .existsSync();
}

Directory? _resolveLibDir(String dirName, Uri packageRoot, OS os) {
  // 1. Local prebuilt (in-tree development override).
  final localDir = Directory.fromUri(
    packageRoot.resolve('native/$kOnnxOrtNamespace/prebuilt/$dirName/'),
  );
  if (_hasMainLib(localDir, os)) return localDir;

  // 2. Shared cache from a previous hook run.
  final cacheDir =
      Directory('${_cacheRootForOrt().path}/$dirName');
  if (_hasMainLib(cacheDir, os)) return cacheDir;

  return null;
}

// ============================================================================
// Download + verify + extract
// ============================================================================

Future<Directory?> _downloadAndExtract(String dirName) async {
  final archiveName = _archiveName(dirName);
  final url = _downloadUrl(dirName);
  if (archiveName == null || url == null) return null;

  final expectedChecksum = kOnnxOrtChecksums[archiveName];
  if (expectedChecksum == null) {
    // No checksum registered → platform not supported. Skip silently.
    return null;
  }

  // Reject placeholder checksums that were never filled in.
  if (expectedChecksum.contains('<') || expectedChecksum.contains('>')) {
    stderr.writeln(
      'flutter_gemma onnx_ort: Checksum placeholder not filled for '
      '$archiveName — skipping $dirName.',
    );
    return null;
  }

  final cacheRoot = _cacheRootForOrt();
  final targetDir = Directory('${cacheRoot.path}/$dirName');
  final archiveFile = File('${cacheRoot.path}/$archiveName');

  try {
    if (!cacheRoot.existsSync()) {
      cacheRoot.createSync(recursive: true);
    }

    stderr.writeln(
      'flutter_gemma onnx_ort: Downloading $archiveName from $url ...',
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln(
          'flutter_gemma onnx_ort: Download failed (HTTP ${response.statusCode})',
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
        'flutter_gemma onnx_ort: Checksum mismatch for $archiveName!',
      );
      stderr.writeln('  Expected: $expectedChecksum');
      stderr.writeln('  Actual:   $actualChecksum');
      archiveFile.deleteSync();
      return null;
    }
    stderr.writeln(
      'flutter_gemma onnx_ort: Checksum verified ($archiveName)',
    );

    // Extract into a sibling temp dir on the SAME filesystem, then rename
    // into place atomically. A torn extract leaves only the temp dir (cleaned
    // in finally), never a half-populated targetDir.
    final tmpDir =
        Directory('${cacheRoot.path}/.tmp-$dirName-$pid');
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    tmpDir.createSync(recursive: true);

    try {
      final flatDir = Directory('${tmpDir.path}/flat');
      flatDir.createSync();

      if (archiveName.endsWith('.aar')) {
        // Android AAR: zip format. Extract jni/arm64-v8a/libonnxruntime.so
        // into flat/libonnxruntime.so.
        await _extractAar(archiveFile, flatDir, dirName);
      } else if (archiveName.endsWith('.zip')) {
        // Windows zip: extract onnxruntime.dll (+ providers_shared.dll)
        // directly from zip root into flat/.
        await _extractZip(archiveFile, flatDir, dirName);
      } else {
        // Linux / macOS .tgz: find the versioned .so / .dylib and copy it
        // to flat/lib<name>.so|dylib.
        await _extractTgz(archiveFile, flatDir, dirName);
      }

      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      flatDir.renameSync(targetDir.path); // atomic on same FS
    } finally {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    }

    archiveFile.deleteSync();
    stderr.writeln(
      'flutter_gemma onnx_ort: libs cached to ${targetDir.path}',
    );
    return targetDir;
  } catch (e) {
    stderr.writeln('flutter_gemma onnx_ort: download/extract failed: $e');
    if (archiveFile.existsSync()) archiveFile.deleteSync();
    return null;
  }
}

/// Extract Linux / macOS `.tgz`. Inside the tarball the versioned dylib lives
/// at `onnxruntime-<platform>-<version>/lib/libonnxruntime.<ext>.<version>`
/// alongside a symlink `libonnxruntime.<ext>`. We copy the real versioned file
/// to `flat/lib$kOnnxOrtMainLibName.<ext>` and the companion if present.
Future<void> _extractTgz(
  File archiveFile,
  Directory flatDir,
  String dirName,
) async {
  // Step 1: extract into a raw temp dir.
  final rawDir = Directory('${flatDir.parent.path}/raw');
  rawDir.createSync();
  final extract = await Process.run('tar', [
    '-xzf',
    archiveFile.path,
    '-C',
    rawDir.path,
  ]);
  if (extract.exitCode != 0) {
    throw Exception('tar failed: ${extract.stderr}');
  }

  // Step 2: find the main lib (versioned file, not the symlink).
  // Use exact suffix matching ('.dylib' or '.so') to avoid picking up
  // dSYM YAML files (e.g. libonnxruntime.1.27.0.dylib.yml) that contain
  // '.dylib' in their name but are not Mach-O binaries.
  final ext = dirName.startsWith('macos_') ? '.dylib' : '.so';
  final libName = 'lib$kOnnxOrtMainLibName';

  // Find all files matching lib<name>*.<ext> (exact suffix).
  // On macOS: libonnxruntime.dylib, libonnxruntime.1.dylib,
  //           libonnxruntime.1.27.0.dylib — all Mach-O. Pick the versioned
  //           one (longest basename ending in .dylib).
  final candidates = <File>[];
  for (final e in rawDir.listSync(recursive: true)) {
    if (e is! File) continue;
    final fname = e.uri.pathSegments.last;
    if (fname.startsWith(libName) && fname.endsWith(ext)) {
      candidates.add(e);
    }
  }
  if (candidates.isEmpty) {
    throw Exception(
      'No $libName$ext found inside ${archiveFile.path}',
    );
  }
  // Pick the file with the longest basename — that's the fully-versioned file
  // (e.g. libonnxruntime.1.27.0.dylib > libonnxruntime.1.dylib >
  // libonnxruntime.dylib). All three are real Mach-O dylibs on macOS.
  File? mainLib;
  for (final c in candidates) {
    if (c.uri.pathSegments.last.length >
        (mainLib?.uri.pathSegments.last.length ?? 0)) {
      mainLib = c;
    }
  }
  mainLib!.copySync('${flatDir.path}/$libName$ext');

  // Step 3: companion lib (providers_shared) on Linux.
  for (final companion in _companions(dirName)) {
    final companionName = 'lib$companion';
    const companionExt = '.so';
    final companionFile = rawDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          final n = f.uri.pathSegments.last;
          return n.startsWith(companionName) && n.endsWith(companionExt);
        })
        .fold<File?>(null, (prev, f) {
          if (prev == null ||
              f.uri.pathSegments.last.length >
                  prev.uri.pathSegments.last.length) {
            return f;
          }
          return prev;
        });
    if (companionFile != null) {
      companionFile.copySync('${flatDir.path}/$companionName$companionExt');
    }
  }

  rawDir.deleteSync(recursive: true);
}

/// Extract Windows `.zip`. DLLs live at the root of the zip:
/// `onnxruntime-win-x64-<version>/lib/onnxruntime.dll` and
/// `onnxruntime_providers_shared.dll`.
Future<void> _extractZip(
  File archiveFile,
  Directory flatDir,
  String dirName,
) async {
  final rawDir = Directory('${flatDir.parent.path}/raw');
  rawDir.createSync();
  final extract = await Process.run('tar', [
    '-xf',
    archiveFile.path,
    '-C',
    rawDir.path,
  ]);
  if (extract.exitCode != 0) {
    throw Exception('tar failed: ${extract.stderr}');
  }

  // Copy main DLL.
  final mainDll = rawDir
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere(
        (f) => f.uri.pathSegments.last == '$kOnnxOrtMainLibName.dll',
        orElse: () => throw Exception(
          '$kOnnxOrtMainLibName.dll not found in ${archiveFile.path}',
        ),
      );
  mainDll.copySync('${flatDir.path}/$kOnnxOrtMainLibName.dll');

  // Copy companion DLLs.
  for (final companion in _companions(dirName)) {
    final companionDll = rawDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last == '$companion.dll')
        .firstOrNull;
    if (companionDll != null) {
      companionDll.copySync('${flatDir.path}/$companion.dll');
    }
  }

  rawDir.deleteSync(recursive: true);
}

/// Extract Android AAR (zip format). The AAR contains:
///   `jni/arm64-v8a/libonnxruntime.so`
/// Copy it to `flat/libonnxruntime.so`.
Future<void> _extractAar(
  File archiveFile,
  Directory flatDir,
  String dirName,
) async {
  final rawDir = Directory('${flatDir.parent.path}/raw');
  rawDir.createSync();
  // AAR is a zip.
  final extract = await Process.run('tar', [
    '-xf',
    archiveFile.path,
    '-C',
    rawDir.path,
  ]);
  if (extract.exitCode != 0) {
    throw Exception('tar (AAR) failed: ${extract.stderr}');
  }

  // The ABI subfolder depends on dirName. For now we only support arm64.
  const abiDir = 'arm64-v8a';
  final soFile = File('${rawDir.path}/jni/$abiDir/lib$kOnnxOrtMainLibName.so');
  if (!soFile.existsSync()) {
    throw Exception(
      'jni/$abiDir/lib$kOnnxOrtMainLibName.so not found in AAR',
    );
  }
  soFile.copySync('${flatDir.path}/lib$kOnnxOrtMainLibName.so');

  rawDir.deleteSync(recursive: true);
}

// ============================================================================
// Per-platform name resolution
// ============================================================================

String? _prebuiltDirName(OS os, Architecture arch, {IOSSdk? iOSSdk}) {
  if (os == OS.iOS) {
    // iOS is BLOCKED (static framework only — not loadable as CodeAsset).
    // Return null to skip all iOS hook processing; the package uses
    // the flutter_onnxruntime CocoaPods dependency instead.
    return null;
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

  final dirName = '${osName}_$archName';

  // macOS x64: BLOCKED (no standalone tarball in v1.27.0+).
  if (dirName == 'macos_x86_64') return null;

  // Verify a URL exists (guards against future dirName mismatches).
  if (_downloadUrl(dirName) == null) return null;

  return dirName;
}

// ============================================================================
// Cross-package version guard
// ============================================================================

({bool present}) _guardAndCheckPresent() {
  final existing = _readMarker();
  if (existing == null) return (present: false);
  if (existing.version == _markerVersion) return (present: true);
  if (existing.owner == _packageName) return (present: false);
  throw StateError(
    'Native library conflict for "$kOnnxOrtNamespace": '
    'this package ($_packageName) needs version $_markerVersion, '
    'but "${existing.owner}" already placed version ${existing.version} '
    'in the shared cache (${_cacheRootForOrt().path}). '
    'Run `flutter clean` and delete the flutter_gemma native cache to reset.',
  );
}

// ============================================================================
// CodeAsset staging (Apple: copy to outputDirectory to avoid Xcode cycle)
// ============================================================================

Uri Function(Uri) _makeStageFn(BuildInput input, OS os) {
  return (Uri srcUri) {
    if (os != OS.macOS && os != OS.iOS) return srcUri;
    final src = File.fromUri(srcUri);
    final destUri = input.outputDirectory.resolve(srcUri.pathSegments.last);
    final dest = File.fromUri(destUri);
    if (!dest.existsSync() || dest.lengthSync() != src.lengthSync()) {
      dest.parent.createSync(recursive: true);
      src.copySync(destUri.toFilePath());
    }
    return destUri;
  };
}

// ============================================================================
// Main processing
// ============================================================================

Future<void> _processOrtBundle({
  required BuildInput input,
  required BuildOutputBuilder output,
  required OS os,
  required String dirName,
}) async {
  final archiveName = _archiveName(dirName);
  if (archiveName == null) return;

  // Skip if no checksum registered for this platform.
  final checksum = kOnnxOrtChecksums[archiveName];
  if (checksum == null) return;

  // Skip placeholder checksums.
  if (checksum.contains('<') || checksum.contains('>')) {
    stderr.writeln(
      'flutter_gemma onnx_ort: Checksum placeholder for $archiveName — '
      'skipping $dirName (compute SHA256 and fill in kOnnxOrtChecksums).',
    );
    return;
  }

  _guardAndCheckPresent();
  _invalidateCacheIfStale();

  var libDir = _resolveLibDir(dirName, input.packageRoot, os);
  libDir ??= await _downloadAndExtract(dirName);
  if (libDir == null) return;

  final mainFileName = _dylibFileName(os, kOnnxOrtMainLibName);
  final mainFileUri = libDir.uri.resolve(mainFileName);
  if (!File.fromUri(mainFileUri).existsSync()) return;

  _writeMarker();

  final stage = _makeStageFn(input, os);

  output.assets.code.add(
    CodeAsset(
      package: _packageName,
      name: 'src/native/$kOnnxOrtMainLibName',
      linkMode: DynamicLoadingBundled(),
      file: stage(mainFileUri),
    ),
  );

  // Companion libraries (providers_shared on Linux + Windows x64).
  for (final companion in _companions(dirName)) {
    final companionFileName = _dylibFileName(os, companion);
    final companionFileUri = libDir.uri.resolve(companionFileName);
    if (File.fromUri(companionFileUri).existsSync()) {
      output.assets.code.add(
        CodeAsset(
          package: _packageName,
          name: 'src/native/$companion',
          linkMode: DynamicLoadingBundled(),
          file: stage(companionFileUri),
        ),
      );
    }
  }

  output.dependencies.add(libDir.uri);
}

// ============================================================================
// Entry point
// ============================================================================

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    // Supported platforms: desktop + Android.
    // iOS: BLOCKED (static xcframework only — use CocoaPods flutter_onnxruntime dep).
    // Web: OUT OF SCOPE (dart:ffi unavailable in WASM).
    if (os != OS.macOS &&
        os != OS.linux &&
        os != OS.windows &&
        os != OS.android) {
      return;
    }

    final arch = codeConfig.targetArchitecture;
    final iOSSdk = os == OS.iOS ? codeConfig.iOS.targetSdk : null;
    final dirName = _prebuiltDirName(os, arch, iOSSdk: iOSSdk);
    if (dirName == null) return; // Unsupported arch or BLOCKED platform.

    await _processOrtBundle(
      input: input,
      output: output,
      os: os,
      dirName: dirName,
    );
  });
}
