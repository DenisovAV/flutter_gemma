// Native Assets hook for the ORT-GenAI text-generation arm (hardened plan
// Phase 3, Task 4). Modeled on `flutter_gemma_litertlm/hook/build.dart`
// (fetch → sha256 → extract → CodeAsset; marker/self-heal; Apple-only
// `stage()`), but sources from **Microsoft's own GitHub releases** — two
// separate repos, NOT the `native-vX` tag this repo publishes for LiteRT-LM
// — so it does not reuse `_NativeBundle`'s tag-based URL construction.
// Document this supply-chain divergence: unlike every other bundle in this
// monorepo, these two archives are never re-hosted by us.
//
// **macOS arm64 only (v1)** — non-macOS archives/shas are a stubbed "pending
// D2" gap (hardened plan device go/no-go), see [_archivesFor].
//
// This hook is the SOLE owner of exactly one `libonnxruntime` (1.27.0) per
// design D1 — the embedding arm's `OrtFfiClient` (`ort_ffi_client.dart`)
// still resolves the dylib directly by platform default name /
// `FLUTTER_GEMMA_ORT_LIBRARY` for now; wiring it onto this CodeAsset is a
// follow-on (it shares the same package, so no cross-package marker
// coordination is needed the way litertlm/embeddings share libLiteRtLm).
import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma_onnx';

/// One archive to fetch, verify, and extract: a GitHub Release tarball for
/// one (library, platform) pair.
class _Archive {
  const _Archive({
    required this.url,
    required this.sha256,
    required this.extractedLibPath,
    required this.assetName,
  });

  /// Full download URL (Microsoft's own release, not ours).
  final String url;

  /// Expected SHA256 of the downloaded `.tar.gz`/`.tgz` bytes.
  final String sha256;

  /// Path to the dylib INSIDE the extracted archive root, e.g.
  /// `lib/libonnxruntime.1.27.0.dylib` — deliberately the concrete
  /// versioned file, not a same-named-copy or a `.1.dylib` symlink (the
  /// symlink chain the vendor ships alongside it; other platforms' archives
  /// only have the true binary at the fully-versioned name).
  final String extractedLibPath;

  /// CodeAsset name (package-relative, no extension) — becomes the
  /// framework/binary leaf name Flutter's macOS build wraps this dylib in
  /// (e.g. `onnxruntime` → `onnxruntime.framework/onnxruntime`). Must match
  /// what `GenAiFfiClient`'s worker-side loader opens
  /// (`DynamicLibrary.open('$assetName.framework/$assetName')` — see Task
  /// 4's framework-wrap risk note in `gen_ai_client.dart`).
  final String assetName;

  String get archiveFileName => url.split('/').last;
}

/// macOS arm64 archives for this version pair. Non-macOS entries are a
/// stubbed "pending D2" gap: Android/iOS are blocked on the device
/// throughput/RAM go/no-go (hardened plan tail), Linux/Windows shas need a
/// real fetch — neither happens in this phase. Returns null for any
/// unsupported (os, arch).
_OrtBundle? _archivesFor(OS os, Architecture arch) {
  if (os == OS.macOS && arch == Architecture.arm64) {
    return const _OrtBundle(
      dirName: 'macos_arm64',
      ort: _Archive(
        url:
            'https://github.com/microsoft/onnxruntime/releases/download/'
            'v1.27.0/onnxruntime-osx-arm64-1.27.0.tgz',
        sha256:
            '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a',
        extractedLibPath:
            'onnxruntime-osx-arm64-1.27.0/lib/libonnxruntime.1.27.0.dylib',
        assetName: 'onnxruntime',
      ),
      genai: _Archive(
        url:
            'https://github.com/microsoft/onnxruntime-genai/releases/'
            'download/v0.14.0/onnxruntime-genai-0.14.0-osx-arm64.tar.gz',
        sha256:
            '56583c98e3939d2cfd5a3812471be44017ce2752776d389015ff583a8d758312',
        extractedLibPath:
            'onnxruntime-genai-0.14.0-osx-arm64/lib/libonnxruntime-genai.dylib',
        assetName: 'onnxruntime-genai',
      ),
    );
  }
  // linux_x64, windows_x64, android arm64, ios arm64/ios_sim_arm64: DEVICE /
  // gated — see the hardened plan's explicit tail. No entry here means the
  // hook silently skips those targets (matches flutter_gemma_litertlm's
  // "no checksum registered → skip" convention); GenAiFfiClient's own
  // dlopen then fails loud at first use with a clear "no such file".
  return null;
}

/// The two archives that make up one platform's bundle, plus the bundle
/// version tag used for the cache marker.
class _OrtBundle {
  const _OrtBundle({
    required this.dirName,
    required this.ort,
    required this.genai,
  });

  final String dirName;
  final _Archive ort;
  final _Archive genai;

  /// Cache-invalidation key — bump whenever either archive's URL/sha changes.
  String get version => 'ort-1.27.0_genai-0.14.0';

  List<_Archive> get archives => [ort, genai];
}

// ============================================================================
// Cache layout (namespaced under this package — no cross-package sharing).
// ============================================================================

Directory _cacheBaseDir() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (Platform.isWindows) {
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
    return Directory('$localAppData\\flutter_gemma\\native\\onnx_genai');
  }
  if (Platform.isMacOS) {
    return Directory('$home/Library/Caches/flutter_gemma/native/onnx_genai');
  }
  return Directory('$home/.cache/flutter_gemma/native/onnx_genai');
}

File _markerFile(_OrtBundle bundle) =>
    File('${_cacheBaseDir().path}/${bundle.dirName}/.version');

String? _readMarkerVersion(_OrtBundle bundle) {
  final m = _markerFile(bundle);
  if (!m.existsSync()) return null;
  try {
    final decoded = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
    final v = decoded['version'];
    return v is String ? v : null;
  } catch (_) {
    return null;
  }
}

void _writeMarker(_OrtBundle bundle) {
  _markerFile(
    bundle,
  ).writeAsStringSync(jsonEncode({'version': bundle.version}));
}

/// Local in-tree prebuilt override — `native/onnx_genai/prebuilt/<dirName>/`,
/// e.g. for a developer who already has the spike's downloaded dylibs and
/// wants to iterate on the hook without re-fetching from GitHub. Absent in
/// normal use; falls through to the cache / download path.
Directory? _localPrebuiltDir(Uri packageRoot, _OrtBundle bundle) {
  final dir = Directory.fromUri(
    packageRoot.resolve('native/onnx_genai/prebuilt/${bundle.dirName}/'),
  );
  final hasBoth = bundle.archives.every(
    (a) => _stagedSourceFile(dir, a).existsSync(),
  );
  return hasBoth ? dir : null;
}

// ============================================================================
// Download + verify + extract
// ============================================================================

Future<bool> _downloadVerifyExtract(_Archive archive, Directory destDir) async {
  final cacheRoot = destDir.parent; // .../onnx_genai/<dirName>/
  if (!cacheRoot.existsSync()) cacheRoot.createSync(recursive: true);
  final archiveFile = File('${cacheRoot.path}/${archive.archiveFileName}');

  try {
    stderr.writeln('flutter_gemma_onnx: downloading ${archive.url} ...');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(archive.url));
      // GitHub release assets 302-redirect to an S3-style signed URL; a
      // plain HttpClient request follows redirects by default, but be
      // explicit since a silent non-follow would produce a 3-byte HTML body
      // that "downloads" successfully and then fails the sha256 check with
      // a confusing mismatch instead of a clear HTTP-status error.
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln(
          'flutter_gemma_onnx: download failed (HTTP ${response.statusCode}) '
          'for ${archive.url}',
        );
        await response.drain<void>();
        return false;
      }
      final sink = archiveFile.openWrite();
      await response.pipe(sink);
    } finally {
      client.close();
    }

    final bytes = await archiveFile.readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != archive.sha256) {
      stderr.writeln(
        'flutter_gemma_onnx: checksum mismatch for ${archive.archiveFileName}\n'
        '  expected: ${archive.sha256}\n'
        '  actual:   $actual',
      );
      archiveFile.deleteSync();
      return false;
    }
    stderr.writeln(
      'flutter_gemma_onnx: checksum verified (${archive.archiveFileName})',
    );

    final tmpDir = Directory('${cacheRoot.path}/.tmp-extract-$pid');
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
          'flutter_gemma_onnx: extract failed for ${archive.archiveFileName}: '
          '${result.stderr}',
        );
        return false;
      }
      final extracted = File('${tmpDir.path}/${archive.extractedLibPath}');
      if (!extracted.existsSync()) {
        stderr.writeln(
          'flutter_gemma_onnx: extracted archive is missing the expected '
          'lib at ${archive.extractedLibPath} — archive layout changed?',
        );
        return false;
      }
      if (!destDir.existsSync()) destDir.createSync(recursive: true);
      final destFileName = extracted.uri.pathSegments.last;
      extracted.copySync('${destDir.path}/$destFileName');
    } finally {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    }
    archiveFile.deleteSync();
    return true;
  } catch (e) {
    stderr.writeln(
      'flutter_gemma_onnx: fetch failed for ${archive.archiveFileName}: $e',
    );
    if (archiveFile.existsSync()) archiveFile.deleteSync();
    return false;
  }
}

/// Extracted lib's on-disk filename inside [destDir] for [archive] — the
/// concrete versioned filename copied out of the archive (e.g.
/// `libonnxruntime.1.27.0.dylib`), not the canonical asset name.
File _stagedSourceFile(Directory destDir, _Archive archive) {
  final fileName = archive.extractedLibPath.split('/').last;
  return File('${destDir.path}/$fileName');
}

// ============================================================================
// Entry point
// ============================================================================

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;
    final arch = codeConfig.targetArchitecture;

    final bundle = _archivesFor(os, arch);
    if (bundle == null) return; // unsupported target this phase — see doc.

    final cacheDir = Directory('${_cacheBaseDir().path}/${bundle.dirName}');
    final localDir = _localPrebuiltDir(input.packageRoot, bundle);
    final storedVersion = _readMarkerVersion(bundle);
    final useCache = localDir == null && storedVersion == bundle.version;

    Directory libDir;
    if (localDir != null) {
      libDir = localDir;
    } else if (useCache && cacheDir.existsSync()) {
      libDir = cacheDir;
    } else {
      // (Re)fetch every archive whose version changed or is missing.
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
      for (final archive in bundle.archives) {
        final ok = await _downloadVerifyExtract(archive, cacheDir);
        if (!ok) return; // clear stderr diagnostics already emitted above.
      }
      _writeMarker(bundle);
      libDir = cacheDir;
    }

    // APPLE-ONLY stage(): copy each dylib into the hook's outputDirectory
    // before registering it as a CodeAsset. Without this, Native Assets
    // would register the CodeAsset straight from the cache dir (which is
    // also listed as a build dependency below) — Xcode's "Flutter Assemble"
    // Run Script then takes a directoryTreeSignature over that input dir,
    // which now contains its own output, producing "Cycle inside Flutter
    // Assemble". Exact same fix as flutter_gemma_litertlm's hook; see that
    // file's longer note. macOS-only in this package (no iOS device support
    // yet), but written OS-gated for when iOS lands.
    // CRITICAL (codex Phase-1 finding, confirmed via a real `flutter build
    // macos`): Flutter's macOS asset-bundling derives each `.framework`'s
    // NAME from the STAGED FILE'S OWN FILENAME, not from the CodeAsset's
    // `name:` field — a naive `stage()` that preserves
    // `libonnxruntime.1.27.0.dylib`'s on-disk name produces
    // `onnxruntime1270.framework/onnxruntime1270` (dots collapsed out of the
    // version suffix), which GenAI's bare-name
    // `dlopen("libonnxruntime.dylib")` and `GenAiFfiClient`'s own
    // `'onnxruntime.framework/onnxruntime'` candidate can never match.
    // [destFileName] renames the staged copy to the CANONICAL bare name
    // (`libonnxruntime.dylib`) so the derived framework is
    // `onnxruntime.framework/onnxruntime` — verified end-to-end below.
    Uri stage(File src, String destFileName) {
      if (os != OS.macOS && os != OS.iOS) return src.uri;
      final destUri = input.outputDirectory.resolve(destFileName);
      final dest = File.fromUri(destUri);
      if (!dest.existsSync() || dest.lengthSync() != src.lengthSync()) {
        dest.parent.createSync(recursive: true);
        src.copySync(destUri.toFilePath());
      }
      return destUri;
    }

    for (final archive in bundle.archives) {
      final src = _stagedSourceFile(libDir, archive);
      if (!src.existsSync()) continue; // shouldn't happen post-fetch; be safe.
      final canonicalFileName = 'lib${archive.assetName}.dylib';
      output.assets.code.add(
        CodeAsset(
          package: _packageName,
          name: 'src/native/${archive.assetName}',
          linkMode: DynamicLoadingBundled(),
          file: stage(src, canonicalFileName),
        ),
      );
    }
    output.dependencies.add(libDir.uri);
  });
}
