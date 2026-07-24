# flutter_gemma_embeddings

On-device text embeddings for [flutter_gemma](https://pub.dev/packages/flutter_gemma):
Gecko / EmbeddingGemma `.tflite` models via the LiteRT C API + `dart:ffi`. Opt-in
package — add it only if you compute embeddings (e.g. for on-device RAG).
Android, iOS, macOS, Linux, Windows, Web.

This package is thin logic that depends on **`flutter_gemma_litertlm`** — the full
LiteRT engine, which owns the shared native library (`libLiteRtLm`) and exposes
the LiteRt interpreter FFI. You get the native library transitively; there is no
separate embeddings build hook.

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

## Web setup

On web, embeddings run via LiteRT.js. Add the loader script to your app's
`web/index.html` `<head>`. Pin a release tag and include a Subresource Integrity
hash so a CDN compromise cannot inject code:

```html
<script type="module"
        src="https://cdn.jsdelivr.net/gh/DenisovAV/flutter_gemma@<tag>/web/litert_embeddings.js"
        integrity="sha384-<hash>"
        crossorigin="anonymous"></script>
```

> Compute the hash for the tag you pin (the browser rejects the script if
> `integrity` doesn't match, so don't ship a placeholder):
> `openssl dgst -sha384 -binary web/litert_embeddings.js | openssl base64 -A`

Native platforms need no setup — the LiteRT native library is bundled at build
time by `flutter_gemma_litertlm`'s Native-Assets hook (a transitive dependency).

## Platforms

| Platform | Support |
|----------|---------|
| Android / iOS | ✅ FFI |
| macOS / Linux / Windows | ✅ FFI |
| Web | ✅ via LiteRT.js (CDN) |

The native library is fetched at build time by `flutter_gemma_litertlm`'s
`hook/build.dart` (Native Assets), a transitive dependency, from a
SHA256-verified GitHub release — no manual setup on native platforms.

## Troubleshooting

### `dlopen` / "library not found" (`libLiteRtLm`)

`flutter_gemma_litertlm` is the sole owner of the shared native library and
bundles it via its build hook. A stale Native-Assets cache after a native
version bump can leave the library unbundled, surfacing as an opaque `dlopen`
"no such file" on the first embedding call. Fix with a clean rebuild:

```bash
flutter clean
rm -rf ~/Library/Caches/flutter_gemma/native        # macOS / Linux
# Windows: rmdir /s "%LOCALAPPDATA%\flutter_gemma\native"  (path may vary)
flutter pub get
```
