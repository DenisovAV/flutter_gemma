# flutter_gemma_embeddings

On-device text embeddings for [flutter_gemma](https://pub.dev/packages/flutter_gemma):
Gecko / EmbeddingGemma `.tflite` models via the LiteRT C API + `dart:ffi`. Opt-in
package — add it only if you compute embeddings (e.g. for on-device RAG).
Android, iOS, macOS, Linux, Windows, Web.

This package is **autonomous**: it does not depend on `flutter_gemma_litertlm`, so
you can use embeddings without pulling in the `.litertlm` inference engine. When
both packages are present they share one native library (`libLiteRtLm`), bundled
once (see Troubleshooting).

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';

await FlutterGemma.initialize(
  embeddingBackends: [LiteRtEmbeddingBackend()],
);
```

`LiteRtEmbeddingBackend` provides the embedding model used by the auto-embedding
RAG methods (`addDocument` / `searchSimilar`) and by `createEmbeddingModel`. Pair
it with a vector store from `flutter_gemma_rag_sqlite` or
`flutter_gemma_rag_qdrant`.

## Platforms

| Platform | Support |
|----------|---------|
| Android / iOS | ✅ FFI |
| macOS / Linux / Windows | ✅ FFI |
| Web | ✅ via LiteRT.js (CDN) |

The native library is fetched at build time by `hook/build.dart` (Native Assets)
from a SHA256-verified GitHub release — no manual setup on native platforms.

## Troubleshooting

### `dlopen` / "library not found" (`libLiteRtLm`) after removing `flutter_gemma_litertlm`

`flutter_gemma_embeddings` and `flutter_gemma_litertlm` share one native library
(`libLiteRtLm`), bundled exactly once by whichever package's build hook ran
first ("the owner"). If you **had both packages, then removed the owner** and
rebuilt **without** a clean, a stale ownership marker in the shared cache can
leave the library unbundled, surfacing as an opaque `dlopen` "no such file" on
the first embedding call. Fix:

```bash
flutter clean
rm -rf ~/Library/Caches/flutter_gemma/native        # macOS / Linux
# Windows: rmdir /s "%LOCALAPPDATA%\flutter_gemma\native"  (path may vary)
flutter pub get
```

This is a known limitation of Dart's Native Assets build hooks: a hook is
sandboxed and cannot detect which sibling packages are present in the current
build, so it cannot recompute the registrant per-build (see
[dart-lang/native#190](https://github.com/dart-lang/native/issues/190)). It only
triggers in the narrow remove-the-owner-without-clean case.
