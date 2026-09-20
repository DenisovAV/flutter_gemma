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

## Teach your AI assistant this package

```bash
dart run skills@ get --all
```

Installs the agent skills `flutter_gemma` bundles — this package depends on it, so they come with it. One of them, `flutter-gemma-rag`, covers embedding models, the vector stores, and metadata filters.

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

On web, `flutter_gemma_litertlm`'s embedding backend runs via LiteRT.js. Copy
all four files from this package's `web/` into your app's `web/`, next to
`index.html` — `litert_embeddings.js` imports the other three by relative path,
so they have to sit together:

```
litert_embeddings.js  sentencepiece.js  litert.js  tensorflow.js
```

They are four pieces of one bundle (the entry plus three vendor chunks), built
together by `tool/web_build`, so never mix them across package versions. Find
this package's directory with
`grep -A1 '"name": "flutter_gemma_embeddings"' .dart_tool/package_config.json`,
then load the entry module from `web/index.html`:

```html
<script type="module" src="litert_embeddings.js"></script>
```

Upgrading from an earlier version: delete the copies in your app's `web/` and
re-copy all four from this version. Before 2.2.0 two of them came from
`flutter_gemma_litertlm/web/`, which no longer has them, and the copies you
have are built against a different `@litertjs/core` than the runtime this
version loads. If you built your own `web/wasm/`, either delete it and take the
CDN default or rebuild it from the version in `LiteRtWebRuntime.pinnedVersion`.

> Earlier versions of this README told you to load `litert_embeddings.js`
> straight from a CDN with a Subresource-Integrity hash. That cannot work: the
> module's three imports are resolved against the CDN path, where two of them
> do not exist (this package ships only two of the four files), so the module
> never executes and every embedding call fails on an undefined global. SRI
> would not have covered the imports either.

### The WASM runtime

LiteRT.js loads a WASM runtime at the first embedding call —
`litert_wasm_internal.js`, or `litert_wasm_compat_internal.js` on a browser
without relaxed SIMD, each with a ~9 MB `.wasm` beside it. Since 2.2.0 they come
from the pinned `@litertjs/core` build on jsDelivr by default — nothing to
install, and nothing this package has to carry into every native-only app.

To serve them yourself (offline, an air-gapped deploy, or a CSP that forbids
third-party script), copy `node_modules/@litertjs/core/wasm/` into your app's
`web/wasm/` and point the package at it before the first embedding:

```dart
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';

LiteRtWebRuntime.wasmPath = '/wasm/';
```

Those files come from `@litertjs/core` — `npm i @litertjs/core@2.5.3` in a
scratch directory, then copy its `wasm/`.

Set the prefix before the first embedding — the runtime is loaded once and
cached, so a later assignment is ignored. LiteRT.js inserts the separator when
it joins the prefix with the file name, so the trailing slash above is
convention, not a requirement; the value is root-absolute, and an app served
under a base href other than `/` needs `/my-app/wasm/` or a full URL.

Pin `@litertjs/core` to `LiteRtWebRuntime.pinnedVersion` if you vendor it. The
runtime and this package's `web/litert.js` are two halves of one release —
`litert.js` calls that release's WASM entry points by name — and a mismatch
fails at the first embedding with something that does not mention versions at
all: a runtime older than the glue gives
`Cannot read properties of undefined (reading 'create')`.

Serving it yourself is also the answer if a third-party script in your app's
runtime path is not acceptable to you: LiteRT.js injects the `<script>` itself,
so the CDN copy carries no Subresource-Integrity hash.

Whatever host you use must send `Access-Control-Allow-Origin` (LiteRT.js sets
`crossOrigin="anonymous"` on the script it injects) and serve `.wasm` as
`application/wasm`.

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

### What the tokenizer loaders return

Both loaders return a tokenizer with any `padding` and `truncation` the file
declares switched OFF: `encode()` gives back bare content, never a fixed-width
row. Width and terminators belong to the profile — `encodeForSiglipEmbedding`
applies SigLIP2's 64-token rule itself — and to the forward pass, which owns the
engine's compiled `seqLen`.

This matters if you build a `ForwardPassDescriptor` by hand: do not expect the
file's `"padding": {"strategy": {"Fixed": 64}}` to have been applied for you.

The loaders throw `StateError` if the resolved `dart_sentencepiece_tokenizer`
accepts the calls that disable those settings and leaves them set anyway. That
is a check on the tokenizer's config, not a guarantee about `encode()`'s output.

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
rm -rf ~/Library/Caches/flutter_gemma/native        # macOS
rm -rf ~/.cache/flutter_gemma/native                # Linux
# Windows: rmdir /s "%LOCALAPPDATA%\flutter_gemma\native"  (path may vary)
flutter pub get
```
