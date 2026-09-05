# flutter_gemma_embeddings

Runtime-agnostic on-device text embedding **pipeline** for
[flutter_gemma](https://pub.dev/packages/flutter_gemma): tokenization,
task-type prefixing, a background-isolate worker, and pooling/normalization,
over the `EmbeddingForwardPass` seam. Android, iOS, macOS, Linux, Windows, Web.

Since 2.0.0 this package ships **no concrete embedding backend** — it depends
only on `flutter_gemma`. Pair it with an engine package that implements
`EmbeddingForwardPass` and registers an `EmbeddingBackendProvider`, e.g.
[`flutter_gemma_litertlm`](https://pub.dev/packages/flutter_gemma_litertlm)'s
`LiteRtEmbeddingBackend` (Gecko / EmbeddingGemma `.tflite` via the LiteRT C
API + `dart:ffi`). Most apps only ever interact with `flutter_gemma_litertlm`
directly — it re-exports the pieces you register.

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(
  embeddingBackends: [LiteRtEmbeddingBackend()],
);
```

`LiteRtEmbeddingBackend` provides the embedding model used by the auto-embedding
RAG methods (`addDocument` / `searchSimilar`) and by `createEmbeddingModel`. Pair
it with a vector store from `flutter_gemma_rag_sqlite` or
`flutter_gemma_rag_qdrant`.

## Web setup

On web, `flutter_gemma_litertlm`'s embedding backend runs via LiteRT.js, using
this package's `web/litert_embeddings.js`. Add the loader script to your app's
`web/index.html` `<head>`. Pin a release tag and include a Subresource Integrity
hash so a CDN compromise cannot inject code:

```html
<script type="module"
        src="https://cdn.jsdelivr.net/gh/DenisovAV/flutter_gemma@<tag>/packages/flutter_gemma_embeddings/web/litert_embeddings.js"
        integrity="sha384-<hash>"
        crossorigin="anonymous"></script>
```

> Compute the hash for the tag you pin (the browser rejects the script if
> `integrity` doesn't match, so don't ship a placeholder):
> `openssl dgst -sha384 -binary web/litert_embeddings.js | openssl base64 -A`

Native platforms need no setup — the LiteRT native library is bundled at build
time by `flutter_gemma_litertlm`'s Native-Assets hook.

## Platforms

| Platform | Support |
|----------|---------|
| Android / iOS | ✅ (via flutter_gemma_litertlm's FFI backend) |
| macOS / Linux / Windows | ✅ (via flutter_gemma_litertlm's FFI backend) |
| Web | ✅ (via flutter_gemma_litertlm's LiteRT.js backend, CDN) |

This package itself is pure Dart with no native/FFI code — the concrete
backend (and its native library) is owned by whichever engine package you add.

## Tokenizer profiles

Three adapters, picked by the model you load — a model's special-token
convention is not negotiable, and using the wrong one corrupts the vector
silently rather than failing:

| profile | convention | loader |
|---|---|---|
| Gemma (SentencePiece) | BOS 2, EOS 1, TaskType prefix | `loadGemmaSentencePieceEmbeddingTokenizer` |
| WordPiece (BERT / MiniLM) | `[CLS]` … `[SEP]` | `WordPieceEmbeddingTokenizer.fromJsonString` / `.fromPath` |
| SigLIP2 text tower | no BOS, one trailing EOS, lowercased, fixed 64-token width | `loadSiglipSentencePieceEmbeddingTokenizer` |

SigLIP2's ONNX export carries no `attention_mask`, and its head does not pool
over the sequence at all — `Siglip2TextModel` takes `last_hidden_state[:, -1, :]`,
the LAST position, which with right-padding is a pad token. So the 64-token width
has to live in the ids: the adapter pads (and truncates) to exactly 64 itself
rather than leaving it to the forward pass, and the pad id is first-order rather
than cosmetic.

`WordPieceEmbeddingTokenizer.fromPath` reads from disk and is **native only**;
on web it throws `UnsupportedError` — fetch the `tokenizer.json` yourself there
and use `fromJsonString`.

### Known limitation: the SigLIP2 profile is not selected automatically

`flutter_gemma_onnx`'s tokenizer loader has two branches — WordPiece, or Gemma.
A SigLIP2 `tokenizer.json` is BPE, so it would fall through to the **Gemma**
adapter, which injects BOS, skips the lowercasing and does not pad to 64: every
id in range, nothing thrown, and a vector that is quietly the wrong point in the
embedding space. The loader therefore **refuses** such a file rather than
embedding it wrongly.

Until a profile selector lands, reach the adapter by building the
`ForwardPassDescriptor` yourself, with
`loadSiglipSentencePieceEmbeddingTokenizer` as its tokenizer factory:

```dart
import 'package:flutter_gemma_embeddings/embedding_tokenizer.dart'
    show loadSiglipSentencePieceEmbeddingTokenizer;
```

That library is native-only, which is why it sits outside the package barrel.

**How the file is recognised.** SigLIP2 and Gemma share a vocabulary, but their
`tokenizer.json` files differ where it counts: SigLIP2 declares
`"padding": {"strategy": {"Fixed": 64}, "pad_id": 0}` and a `post_processor` of
`[Sequence A, <eos>]`, while a Gemma tokenizer has `"padding": null` and
`[<bos>, Sequence A]`. `isSiglip2TokenizerJson`
(`package:flutter_gemma_embeddings/tokenizer_convention.dart` — web-safe, so an
engine's web arm can apply the same rule) reads exactly those two blocks, and
requires both: plenty of models declare one alone.

### The task-type prefix

`TaskType` has two values and both prefixes are non-empty, and
`generateEmbedding` defaults to `TaskType.retrievalQuery` — so no caller can
embed without one. That is the intended contract for Gemma/Gecko.

It is not for a CLIP-family tower, whose vision side encodes an image with no
prefix at all, so **the SigLIP2 profile drops it**. Honoring one would put query
and document of the same string on two different points, both off the space the
two towers exist to share.

`WordPieceEmbeddingTokenizer` (MiniLM and other BERT-style models) still
concatenates the prefix. Those models are not trained with EmbeddingGemma's
prefixes either; making that configurable belongs with the profile selector.

## Building a new engine backend

Implement `EmbeddingForwardPass` (`load`/`run`/`close`/`outputDimension`/
`inputSequenceLength`) for your engine, expose a top-level factory tear-off
for it, and build an `EmbeddingBackendProvider` that calls
`CommonEmbeddingModel.create(descriptor: ForwardPassDescriptor(...), tokenizerPath: ...)`.
Declare `EmbeddingOutputContract.pooledFinal` if your engine's forward pass
already returns the final embedding, or `.tokenLevel` if it returns raw
per-token hidden states for this package's `meanPoolAndNormalize` to pool.
See `flutter_gemma_litertlm`'s `lib/src/embedding/` for a worked example.

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
