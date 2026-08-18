// Locates the prebuilt vec0 loadable extension for host-side tests.
//
// Every suite here needs the same artifact, and each used to spell the lookup
// itself — one defaulting to `/tmp/vec0_poc/vec0.dylib`, a path left over from
// the migration proof-of-concept. Nothing puts a file there, so the keystone
// test was red on every machine where someone had not hand-downloaded one, and
// 23 more suites skipped themselves for the same reason. Since CI ran only
// packages/flutter_gemma, nobody saw either.
//
// The artifact is in this repository — `native/sqlite_vec/prebuilt/<plat>/` —
// so that is the default. $VEC0_DYLIB still wins, for pointing at a different
// build.
library;

import 'dart:io';

/// Host-platform subdirectory under `native/sqlite_vec/prebuilt/`.
/// Null on a host we ship no loadable for (tests run on the host, so the
/// iOS/Android prebuilts are never the answer here).
String? get _hostPrebuiltDir {
  if (Platform.isMacOS) return 'macos_arm64';
  if (Platform.isWindows) return 'windows_x86_64';
  if (Platform.isLinux) {
    // No reliable arch probe in dart:io; prefer x86_64 and fall back to arm64
    // by existence, which `vec0Path` does below.
    return 'linux_x86_64';
  }
  return null;
}

String get _libName {
  if (Platform.isMacOS) return 'libvec0.dylib';
  if (Platform.isWindows) return 'vec0.dll';
  return 'libvec0.so';
}

/// Every path considered, in order. Exposed so a failure message can name them
/// all — "not found" and "looked in the wrong place" must not read alike.
List<String> get vec0Candidates {
  final env = Platform.environment['VEC0_DYLIB'];
  final out = <String>[if (env != null && env.isNotEmpty) env];

  // Tests run from the package directory (tool/test_all.sh guarantees it).
  const base = 'native/sqlite_vec/prebuilt';
  final host = _hostPrebuiltDir;
  if (host != null) out.add('$base/$host/$_libName');
  if (Platform.isLinux) out.add('$base/linux_arm64/$_libName');
  return out;
}

/// First candidate that exists, or null when none does.
String? get vec0Path {
  for (final p in vec0Candidates) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// Reason string for `skip:` when the extension is genuinely unavailable, or
/// null when it is present. Names every path tried, and the working directory,
/// because a wrong CWD and a missing file otherwise produce the same message.
String? get vec0SkipReason {
  if (vec0Path != null) return null;
  return 'vec0 loadable extension not found. Looked in: '
      '${vec0Candidates.join(", ")} (cwd: ${Directory.current.path}). '
      'Run from the package directory, or set \$VEC0_DYLIB.';
}
