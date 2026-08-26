// Native Assets hook for flutter_gemma_rag_sqlite.
//
// Registers the per-platform `sqlite-vec` (`vec0`) loadable extension as a
// CodeAsset so the bundled library is resolvable at runtime via
// `DynamicLibrary.open` (see SqliteVectorStore._resolveVec0Path).
//
// Unlike the litert/qdrant hooks (which fetch tens-of-MB libraries from a GitHub
// Release), the vec0 loadables are tiny (~140 KB each, ~1 MB total for all 7
// targets) so they are committed straight into the package under
// `native/sqlite_vec/prebuilt/<target>/` and read locally — no download, no
// checksum, no network step on `pub get`. The android `.so` there is OUR
// rebuild from the amalgamation with 16 KB ELF LOAD-segment alignment
// (`-Wl,-z,max-page-size=16384`) for Android 15 / Play targetSdk 35+ (#319);
// the rest are asg017 upstream loadables. Regenerate them all with
// `native/sqlite_vec/build_local.sh`.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'flutter_gemma_rag_sqlite';

/// Logical CodeAsset name (the runtime resolves the bundled file by its
/// filename; this is just the asset identity inside the package).
const _assetName = 'src/native/vec0';

/// Targets we ship a prebuilt `vec0` for. The set is exactly the directories
/// present under `native/sqlite_vec/prebuilt/`.
const Set<String> _supportedTargets = {
  'android_arm64',
  'ios_arm64',
  'ios_sim_arm64',
  'linux_x86_64',
  'linux_arm64',
  'macos_arm64',
  'windows_x86_64',
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
/// Apple, `<name>.dll` on Windows. The committed prebuilts already use this
/// exact name (see `native/sqlite_vec/build_local.sh`).
String _bundledFileName(OS os) => switch (os) {
  OS.windows => 'vec0.dll',
  OS.macOS || OS.iOS => 'libvec0.dylib',
  _ => 'libvec0.so',
};

// ============================================================================
// Entry point
// ============================================================================

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;

    // Native platforms only — web uses the custom vec0 wasm (dart:ffi is blocked
    // in WASM).
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
    if (dirName == null || !_supportedTargets.contains(dirName)) {
      return; // unsupported target — runtime fails with a clear dlopen error
    }

    final bundledName = _bundledFileName(os);
    final srcUri = input.packageRoot.resolve(
      'native/sqlite_vec/prebuilt/$dirName/$bundledName',
    );
    final srcFile = File.fromUri(srcUri);
    if (!srcFile.existsSync()) {
      // The target is supported (we passed the _supportedTargets check above),
      // so a committed prebuilt MUST exist — its absence means our packaging is
      // broken. Fail the build loudly here rather than register nothing and let
      // the app crash at the first DynamicLibrary.open with an opaque dlopen
      // error that doesn't point back to this hook.
      throw StateError(
        'flutter_gemma_rag_sqlite: sqlite-vec prebuilt missing for $dirName at '
        '$srcUri. The package is supposed to ship it under '
        'native/sqlite_vec/prebuilt/ — regenerate with '
        'native/sqlite_vec/build_local.sh.',
      );
    }

    // APPLE-ONLY staging (Xcode "Cycle inside Flutter Assemble"): copy the dylib
    // into the hook's outputDirectory so the registered output asset does not
    // live inside the package source tree. Windows/Linux register straight from
    // the prebuilt dir. Mirrors the litert/qdrant hooks.
    // Cheap enough at this size (the loadables are ~150 KB) and immune to the
    // size collision above.
    bool sameBytes(File a, File b) {
      if (a.lengthSync() != b.lengthSync()) return false;
      final x = a.readAsBytesSync();
      final y = b.readAsBytesSync();
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
      return true;
    }

    Uri stage(Uri uri) {
      if (os != OS.macOS && os != OS.iOS) return uri;
      final src = File.fromUri(uri);
      final destUri = input.outputDirectory.resolve(uri.pathSegments.last);
      final dest = File.fromUri(destUri);
      // Compare CONTENT, not length.
      //
      // The staged directory name is a hash of the build CONFIG — no package
      // version, no package root — so it is the same path across an upgrade,
      // and it lives in the app's `.dart_tool`, which `pub upgrade` never
      // touches. A size-only guard therefore keeps the previous release's file
      // whenever the new one happens to be the same size.
      //
      // That is not hypothetical here: re-stamping `ios_arm64/libvec0.dylib`
      // from LC_VERSION_MIN_IPHONEOS to LC_BUILD_VERSION took the extra 8
      // bytes out of Mach-O header slack, so the device slice — the only one
      // App Store Connect can reject — went 158440 -> 158440. A consumer
      // upgrading without `flutter clean` would have shipped the old binary
      // and hit the exact rejection this release fixes, while the hook
      // reported success and the source tree looked correct.
      //
      // This is the one hook in the repo whose source is a committed file
      // edited in place; the others read from a version-keyed download cache,
      // where a same-size in-place edit is not the update mechanism.
      if (!dest.existsSync() || !sameBytes(src, dest)) {
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
    output.dependencies.add(srcUri);
  });
}
