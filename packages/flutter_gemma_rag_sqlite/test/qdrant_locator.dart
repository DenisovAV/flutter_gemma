// Locates the qdrant-edge FFI library for host-side tests, the same way
// vec0_locator.dart locates the sqlite-vec loadable.
//
// The library is NOT built here and is not in the repository. It is DOWNLOADED,
// exactly like the LiteRT natives: flutter_gemma_rag_qdrant's hook/build.dart
// fetches `qdrant-edge-<platform>.tar.gz` from the GitHub release, verifies its
// SHA256, and caches it. Running `flutter test` in a package that depends on
// rag_qdrant runs that hook, so both the per-package Native Assets output and
// the shared cache are populated as a side effect — no cargo, no CI step.
//
// What does NOT work is letting QdrantEdgeClient resolve it on its own: outside
// a built app it looks for the bundled name and fails with "native library not
// found for macos". That is the same gap vec0 has, and the same fix — point the
// client at the file the hook already downloaded.
//
// An earlier draft of the parity suite reached for a cargo target directory
// instead. That worked on the one machine that had run cargo, which is the
// property a test must not have.
library;

import 'dart:io';

/// Host-platform subdirectory name used by the hook's cache layout.
String? get _hostDir {
  if (Platform.isMacOS) return 'macos_arm64';
  if (Platform.isWindows) return 'windows_x86_64';
  if (Platform.isLinux) {
    final arch = _unameMachine();
    if (arch == 'aarch64' || arch == 'arm64') return 'linux_arm64';
    return 'linux_x86_64';
  }
  return null;
}

String? _unameMachine() {
  try {
    final r = Process.runSync('uname', const ['-m']);
    if (r.exitCode != 0) return null;
    return r.stdout.toString().trim();
  } on ProcessException {
    return null;
  }
}

String get _libName {
  if (Platform.isMacOS) return 'libqdrant_edge_ffi.dylib';
  if (Platform.isWindows) return 'qdrant_edge_ffi.dll';
  return 'libqdrant_edge_ffi.so';
}

/// Root the hook caches downloaded bundles under, mirroring `_cacheBaseDir()`
/// in hook/build.dart. Kept in sync by hand; the candidate list below tries the
/// per-package Native Assets output first, so a drift here degrades to "one
/// fewer candidate" rather than to a failure.
String? get _cacheBase {
  final env = Platform.environment;
  if (Platform.isWindows) {
    final local = env['LOCALAPPDATA'];
    return local == null ? null : '$local\\flutter_gemma\\native';
  }
  final home = env['HOME'];
  if (home == null) return null;
  if (Platform.isMacOS) return '$home/Library/Caches/flutter_gemma/native';
  return '$home/.cache/flutter_gemma/native';
}

/// Every path tried, in order. Named so the skip reason can list them.
///
/// The ORDER copies flutter_gemma_litertlm's `_devLiteRtLmCandidates`, and both
/// of its choices are there because of an incident, not a preference:
///
///   * the hook's CACHE comes before any local artifact. The cache is
///     version-validated by hook/build.dart (`_readMarker` /
///     `_invalidateBundleCacheIfStale`); a build output is not. They hold the
///     same bytes today, and after the next `qdrant-edge-v*` bump a stale local
///     copy would silently shadow the refreshed download, so host tests would
///     run against a different native version than the app ships.
///   * the package-relative paths WALK UP from the working directory instead of
///     assuming it. litertlm's comment records what assuming costs: the error
///     named a path and said "not found", so it read as "the library was never
///     built" rather than "I looked in the wrong place", and nine speech tests
///     sat red under that misreading.
///
/// $QDRANT_DYLIB stays first: it is an explicit instruction from whoever ran
/// the tests, and overriding it would make the override useless.
List<String> get qdrantCandidates {
  final out = <String>[];

  final override = Platform.environment['QDRANT_DYLIB'];
  if (override != null && override.isNotEmpty) out.add(override);

  // The version-validated download.
  final base = _cacheBase;
  final host = _hostDir;
  if (base != null && host != null) {
    out.add('$base/qdrant_edge/$host/$_libName');
  }

  // The hook's Native Assets output, found by walking up rather than by
  // assuming the working directory is the package root.
  final osDir = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';
  const pkg = 'packages/flutter_gemma_rag_sqlite';
  var dir = Directory.current.absolute;
  for (var hop = 0; hop < 8; hop++) {
    out.add('${dir.path}/build/native_assets/$osDir/$_libName');
    out.add('${dir.path}/.dart_tool/lib/$_libName');
    out.add('${dir.path}/$pkg/build/native_assets/$osDir/$_libName');
    out.add('${dir.path}/$pkg/.dart_tool/lib/$_libName');
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return out;
}

/// First candidate that exists, or null when none does.
String? get qdrantPath {
  for (final p in qdrantCandidates) {
    if (File(p).existsSync()) return File(p).absolute.path;
  }
  return null;
}

/// Reason string for `skip:`, or null when the library is present.
String? get qdrantSkipReason {
  if (qdrantPath != null) return null;
  return 'qdrant-edge library not found. Looked in: '
      '${qdrantCandidates.join(", ")} (cwd: ${Directory.current.path}). '
      'It is downloaded by flutter_gemma_rag_qdrant/hook/build.dart — run '
      '`flutter test` once in that package, or set \$QDRANT_DYLIB.';
}
