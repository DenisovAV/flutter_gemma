// Locates the qdrant-edge FFI library for host-side tests.
//
// The library is NOT built here and is not in the repository: it is DOWNLOADED
// by flutter_gemma_rag_qdrant/hook/build.dart, exactly like the LiteRT natives.
// `flutter test` runs that hook, so the file is on disk before this reads it.
//
// What does NOT work is letting QdrantEdgeClient resolve it on its own: outside
// a built app it looks for the bundled name and fails with "native library not
// found for macos". Same gap vec0 has, same fix -- hand it the downloaded file.
//
// The search order lives in core's host_native_library.dart, shared with vec0
// and litertlm. See it for why the cache outranks a local build and why the
// relative paths are walked up rather than assumed.
library;

import 'dart:io';

import 'package:flutter_gemma/core/utils/host_native_library.dart';

String get _libName => hostNativeLibraryFileName('qdrant_edge_ffi');

/// Every path tried, in order.
List<String> get qdrantCandidates {
  final osDir = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';
  const pkg = 'packages/flutter_gemma_rag_sqlite';
  return hostNativeLibraryCandidates(
    libFileName: _libName,
    envOverride: Platform.environment['QDRANT_DYLIB'],
    cacheNamespace: 'qdrant_edge',
    relativePaths: [
      // The hook's Native Assets output for this package.
      'build/native_assets/$osDir/$_libName',
      '.dart_tool/lib/$_libName',
      '$pkg/build/native_assets/$osDir/$_libName',
      '$pkg/.dart_tool/lib/$_libName',
    ],
  );
}

/// First candidate that exists, or null when none does.
String? get qdrantPath => firstExistingPath(qdrantCandidates);

/// Reason string for `skip:`, or null when the library is present.
String? get qdrantSkipReason {
  if (qdrantPath != null) return null;
  return 'qdrant-edge library not found. Looked in: '
      '${qdrantCandidates.join(", ")} (cwd: ${Directory.current.path}). '
      'It is downloaded by flutter_gemma_rag_qdrant/hook/build.dart -- run '
      '`flutter test` once in that package, or set \$QDRANT_DYLIB.';
}
