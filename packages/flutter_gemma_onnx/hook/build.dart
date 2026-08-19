// Native Assets hook for the ORT-GenAI text-generation arm (hardened plan
// Phase 3, Task 4). Modeled on `flutter_gemma_litertlm/hook/build.dart`
// (fetch → sha256 → extract → CodeAsset; marker/self-heal; Apple-only
// `stage()`), but sources from **Microsoft's own GitHub releases** — two
// separate repos, NOT the `native-vX` tag this repo publishes for LiteRT-LM
// — so it does not reuse `_NativeBundle`'s tag-based URL construction.
// Document this supply-chain divergence: unlike every other bundle in this
// monorepo, these two archives are never re-hosted by us.
//
// **macOS arm64, linux_x64, windows_x64 (v1)** — Android/iOS are a stubbed
// "pending D2" gap (device throughput/RAM go/no-go, not archive
// availability; Android's own archive is also a differently-shaped AAR, see
// [_archivesFor]'s doc). `stage()`'s canonical-rename copy applies on
// macOS/iOS (framework-name derivation) AND Linux (Microsoft's tarball ships
// the versioned `.so.X.Y.Z`, not the bare name `_candidateNames` dlopens) —
// Windows stays a no-op, both because its `.dll`s already ship under the
// bare canonical name and because active staging is what breaks Windows
// cancel/close (see CLAUDE.md's build-native scar).
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

/// Archives for this version pair, keyed by (os, arch). macOS arm64,
/// linux_x64, and windows_x64 are landed (host-fetchable, no device
/// involved — hardened plan Task 4a). Android/iOS stay a stubbed "pending
/// D2" gap: they're blocked on the device throughput/RAM go/no-go, not on
/// archive availability — see the hardened plan's explicit tail. Returns
/// null for any unsupported (os, arch).
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
  if (os == OS.linux && arch == Architecture.x64) {
    return const _OrtBundle(
      dirName: 'linux_x64',
      ort: _Archive(
        url:
            'https://github.com/microsoft/onnxruntime/releases/download/'
            'v1.27.0/onnxruntime-linux-x64-1.27.0.tgz',
        sha256:
            '547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f',
        extractedLibPath:
            'onnxruntime-linux-x64-1.27.0/lib/libonnxruntime.so.1.27.0',
        assetName: 'onnxruntime',
      ),
      genai: _Archive(
        url:
            'https://github.com/microsoft/onnxruntime-genai/releases/'
            'download/v0.14.0/onnxruntime-genai-0.14.0-linux-x64.tar.gz',
        sha256:
            '7b37f13619ee01263278fb1c24a950e219d75c9fa90586b1623d3e8bab9076b0',
        extractedLibPath:
            'onnxruntime-genai-0.14.0-linux-x64/lib/libonnxruntime-genai.so',
        assetName: 'onnxruntime-genai',
      ),
    );
  }
  if (os == OS.windows && arch == Architecture.x64) {
    return const _OrtBundle(
      dirName: 'windows_x64',
      ort: _Archive(
        url:
            'https://github.com/microsoft/onnxruntime/releases/download/'
            'v1.27.0/onnxruntime-win-x64-1.27.0.zip',
        sha256:
            'c5c81710938e68079ff1a192b04897faabe4b43830d48f39f27ecd4e16138bfc',
        extractedLibPath: 'onnxruntime-win-x64-1.27.0/lib/onnxruntime.dll',
        assetName: 'onnxruntime',
      ),
      genai: _Archive(
        url:
            'https://github.com/microsoft/onnxruntime-genai/releases/'
            'download/v0.14.0/onnxruntime-genai-0.14.0-win-x64.zip',
        sha256:
            '8a303e52dc7be8fb2a5331929af451a25ac59774102d7fd09ef673adc85c5ebf',
        extractedLibPath:
            'onnxruntime-genai-0.14.0-win-x64/lib/onnxruntime-genai.dll',
        assetName: 'onnxruntime-genai',
      ),
    );
  }
  // android arm64, ios arm64/ios_sim_arm64: DEVICE-gated — blocked on the
  // hardened plan's throughput/RAM go/no-go, not archive availability.
  // Android's own archive is an AAR (a zip containing per-ABI .so files
  // under jni/<abi>/, plus AndroidManifest.xml/classes.jar noise this hook
  // has no use for) rather than a flat tarball like every other platform
  // here — extracting the right per-ABI .so out of that layout is its own
  // small chunk of work, deliberately left for whoever actually runs the
  // Android go/no-go gate rather than landed speculatively. No entry means
  // the hook silently skips those targets (matches flutter_gemma_litertlm's
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
      // Windows archives (ORT/ORT-GenAI's own release layout) are PKZIP, not
      // tar.gz — `-z` unconditionally forces a gzip decompress pass, which
      // fails outright on a real .zip (true of both GNU tar and bsdtar).
      // Every Windows box since 10 (build 17063) ships `tar.exe` as bsdtar,
      // which auto-detects the container format (including zip) from
      // `-xf` alone — this hook only ever needs `.zip` handling ON Windows
      // (macOS/Linux archives here are always `.tar.gz`/`.tgz`), so bsdtar's
      // availability there is guaranteed, not an assumption about the host.
      final isZip = archive.archiveFileName.toLowerCase().endsWith('.zip');
      final result = await Process.run('tar', [
        if (isZip) '-xf' else '-xzf',
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
    //
    // LINUX gets the same treatment for a different reason: Microsoft's own
    // Linux tarballs ship the concrete versioned file
    // (`libonnxruntime.so.1.27.0`), not the bare `libonnxruntime.so` name
    // `GenAiFfiClient`'s `_candidateNames` bare-name dlopen looks for — copy
    // + rename closes that gap, same as the macOS framework-name fix above.
    // WINDOWS stays a no-op: its .dll archives already ship under the bare
    // canonical name (`onnxruntime.dll`), so no rename is needed — and
    // CLAUDE.md's build-native scar warns that ACTIVE staging on Windows
    // (splitting companion DLLs) is what hangs cancel/close, so this
    // deliberately does not opt Windows in even though it would be a no-op
    // byte-for-byte copy today.
    Uri stage(File src, String destFileName) {
      if (os != OS.macOS && os != OS.iOS && os != OS.linux) return src.uri;
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
      final canonicalFileName = switch (os) {
        OS.linux => 'lib${archive.assetName}.so',
        OS.windows => '${archive.assetName}.dll',
        _ => 'lib${archive.assetName}.dylib',
      };
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
