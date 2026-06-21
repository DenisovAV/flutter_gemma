# ONNX Inference + Embedding Plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Loop-friendly:** Phases are independently testable and ordered by risk. Phase A (embedder) ships standalone value on all 6 platforms before any generator work. Spikes (S1–S3) front-load the generator's unknowns. A loop should execute phase-by-phase, gating each on its verification block, and STOP at a spike that returns a blocking unknown (escalate to human).

**Goal:** Add two opt-in ONNX packages to the flutter_gemma monorepo — `flutter_gemma_onnx_embeddings` (text embeddings via plain ONNX Runtime, all 6 platforms) and `flutter_gemma_onnx` (text generation via onnxruntime-genai, 5 native platforms) — each with unit + FFI + integration tests on every supported platform, native-asset distribution hooks, and a CI matrix.

**Architecture:** Two independent packages, each implementing core provider contracts (`EmbeddingBackendProvider` / `InferenceEngineProvider`) and shipping its OWN SHA-verified native bundle via a Dart Native-Assets `hook/build.dart` (no shared-lib coordination — ORT-GenAI and plain ORT are distinct libraries). The embedder uses plain `onnxruntime` (single-shot `session.run`); the generator binds the `onnxruntime-genai` C API (`ort_genai_c.h`) via `dart:ffi` for the autoregressive loop (KV-cache, sampling). Integration tests live in the shared `packages/flutter_gemma/example/integration_test/` and run per-platform via `flutter test -d <device>` (native) / `flutter drive -d chrome` (web).

**Tech Stack:** Dart 3.12 / Flutter 3.44, melos 7 + pub workspaces, `dart:ffi` + `ffigen`, Dart Native-Assets `hook/build.dart`, ONNX Runtime 1.27 + onnxruntime-genai 0.14.x, `onnxruntime-web` (WASM) for web embeddings, GitHub Actions matrix.

## Global Constraints

- Workspace member rules (from existing packages): each new package adds `resolution: workspace`; `flutter_lints: ^6.0.0`; SDK `>=3.12.0 <4.0.0`; Flutter `>=3.44.0`; `repository: https://github.com/DenisovAV/flutter_gemma`, `homepage: …/tree/main/packages/<name>`. Register the package path in the root `pubspec.yaml` `workspace:` list.
- Provider contracts to implement (verbatim from `packages/flutter_gemma/lib/core/registry/`): `InferenceEngineProvider { String name; int priority=0; bool canHandle(InferenceModelSpec); Future<InferenceModel> createModel(InferenceModelSpec, RuntimeConfig); }` and `EmbeddingBackendProvider { String name; int priority=0; bool canHandle(EmbeddingModelSpec); Future<EmbeddingModel> createModel(EmbeddingModelSpec, RuntimeConfig); }`.
- `RuntimeConfig` fields available (verbatim): `maxTokens, modelPath, tokenizerPath?, preferredBackend?, supportImage, supportAudio, maxNumImages?, enableSpeculativeDecoding?, maxConcurrentSessions?, loraRanks?`.
- File-extension routing: ONNX models are `.onnx` (+ optional `.onnx_data` external weights, or `.ort`). `canHandle` returns true for these.
- Native distribution: copy the `hook/build.dart` pattern from `packages/flutter_gemma_litertlm/hook/build.dart` (`NativeLibraryConfig` with `namespace`, `releaseTagPrefix`, `archivePrefix`, `mainLibName`, `companions`, `markerFileName`, `useFlatLayout`). ONNX uses INDEPENDENT bundles (NO shared marker coordination). SHA256 verification is mandatory — fetch the digest from the GitHub Releases REST API per-asset `digest` field (no sidecar files); for self-hosted bundles, the three-way checksum rule applies (served bytes == `checksums_*.txt` == `_checksums` map in hook).
- The generator hook fetches **TWO** archives per desktop platform: `onnxruntime-genai` (~10 MB) + plain `onnxruntime` (~15-20 MB). **The EMBEDDER has NO custom native-asset hook** — it depends on `flutter_onnxruntime: ^1.8.0` which delivers libonnxruntime on all platforms via CocoaPods (iOS/macOS), Gradle/Maven (Android), and CMake (Linux/Windows). The TWO-archive custom hook applies to the GENERATOR only (Phase C / Task C2).
- On-device execution provider = **CPU only for v1** (no official mobile GPU prebuilt; GPU is a later opt-in on Win/Linux-x64 via separate `-cuda`/`-directml` bundles). Do not wire NNAPI/CoreML/QNN/DirectML/CUDA in v1.
- Web: generation is IMPOSSIBLE (ORT-GenAI has no WASM build). The embedder reaches web via `onnxruntime-web`; the generator package targets 5 native platforms only.
- Test taxonomy (mirror litertlm, see `docs/research/2026-06-21-litertlm-test-release-pattern.md`): host unit tests in `test/` (pure-Dart fakes, NEVER dlopen, run via `flutter test` with no device); integration tests in `packages/flutter_gemma/example/integration_test/` run per-platform via `flutter test integration_test/<f>.dart -d <device>` (native, never `flutter drive`) or `chromedriver & flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<f>.dart -d chrome` (web).
- Commit messages: NO `Co-Authored-By` trailer, NO "Generated with Claude Code" footer.
- Work in an isolated git worktree off `origin/main` (create via the using-git-worktrees skill before Phase A).
- Each package must pass `dart pub publish --dry-run` (0 warnings) before it is considered done.

---

## Phase S — Spikes (front-loaded generator unknowns; a loop STOPS and escalates if any returns BLOCKED)

### Task S1: Spike — plain ONNX Runtime native bundle availability + layout per platform

**Files:** Create `docs/research/spikes/S1-plain-ort-bundles.md` (findings only — no code).

**Interfaces:** Produces a documented per-platform table of: plain-ORT prebuilt source (URL), archive layout (which `libonnxruntime.*` files), exact size, and SHA256 availability. Phases A and C consume this for their hooks.

- [ ] **Step 1: Resolve the plain-ORT native artifact per platform.** For each of Android (arm64-v8a/.so), iOS (xcframework), macOS (arm64/x64 dylib), Windows (x64 dll), Linux (x64 so), Web (onnxruntime-web npm WASM): find the official Microsoft prebuilt download URL, the files it contains, the unpacked size, and whether a SHA256 is published (GitHub release digest, Maven `.sha1`/`.md5`, npm integrity). Record in the doc as a table.
- [ ] **Step 2: Decide self-host vs direct-fetch.** Document whether the hook fetches from Microsoft's official channels directly (preferred, with their published checksums) or re-hosts bundles on the `DenisovAV/flutter_gemma` releases (like litertlm `native-vX`) with `checksums_onnx.txt`. Record the decision + rationale.
- [ ] **Step 3: Commit the spike doc.**
```bash
git add docs/research/spikes/S1-plain-ort-bundles.md
git commit -m "docs(spike): resolve plain ONNX Runtime native bundle layout + checksums per platform"
```
**STOP/escalate if:** no fetchable+verifiable plain-ORT prebuilt exists for a required platform (would block that platform).

### Task S2: Spike — ORT-GenAI desktop two-archive fetch + iOS xcframework codesign

**Files:** Create `docs/research/spikes/S2-genai-desktop-ios.md`.

**Interfaces:** Produces: confirmed two-archive desktop fetch recipe (genai + plain ORT, both SHA-verified) and an iOS xcframework packaging/codesign recipe (or a verdict that iOS generation is deferred to v2). Phase C consumes this.

- [ ] **Step 1: Desktop two-archive recipe.** For Win-x64/macOS-arm64/Linux-x64, document the exact ORT-GenAI release asset (`onnxruntime-genai-<os>-<arch>-<ver>.tar.gz/.zip`) + the matching plain-ORT asset, their per-asset SHA256 from the Releases API, and the in-archive layout (`libonnxruntime-genai.*` + where `libonnxruntime.*` must land so the loader's `NEEDED` resolves). Confirm both register as Native-Assets CodeAssets.
- [ ] **Step 2: iOS xcframework recipe.** Download `onnxruntime-genai-ios-0.14.x.zip`, verify it unpacks to `onnxruntime-genai.xcframework` with device+sim slices, and test whether issue #1335's symlink/codesign defect reproduces on the current version. Document the strip/re-sign steps needed (or conclude iOS generation is deferred — set a flag the plan's Phase C reads).
- [ ] **Step 3: Commit.**
```bash
git add docs/research/spikes/S2-genai-desktop-ios.md
git commit -m "docs(spike): ORT-GenAI desktop two-archive fetch + iOS xcframework codesign recipe"
```
**STOP/escalate if:** iOS xcframework cannot be packaged without an unresolved codesign defect AND the user requires iOS generation in v1 (otherwise: defer iOS, continue).

### Task S3: Spike — ffigen bindings for ort_genai_c.h + onnxruntime_c_api.h

**Files:** Create `docs/research/spikes/S3-ffigen.md`; throwaway `packages/_onnx_ffigen_spike/` (deleted after, or kept as the seed for Phase C).

**Interfaces:** Produces a working `ffigen` config that generates Dart bindings for both `ort_genai_c.h` (generator) and `onnxruntime_c_api.h` (embedder), and a minimal smoke that calls `OgaCreateModel`/`OrtCreateEnv` against a downloaded lib on the host (macOS). Phases A/C consume the ffigen configs.

- [ ] **Step 1: Obtain the C headers** for ORT-GenAI 0.14.x (`ort_genai_c.h`) and ONNX Runtime 1.27 (`onnxruntime_c_api.h`) from the official repos at the pinned versions; record their URLs/commit SHAs.
- [ ] **Step 2: Write `ffigen.yaml`** for each and generate `*_bindings.g.dart`. Confirm key symbols bind: generator `OgaCreateModel`, `OgaCreateGeneratorParams`, `OgaGenerator_GenerateNextToken`, `OgaCreateTokenizer`; embedder `OrtCreateEnv`, `OrtCreateSession`, `OrtRun`, `OrtGetTensorMutableData`.
- [ ] **Step 3: Host smoke.** On macOS, `dlopen` the downloaded `libonnxruntime-genai.dylib` (+ `libonnxruntime.dylib`) and call `OgaCreateModel` on a tiny ONNX-GenAI model (e.g. a small Phi/Gemma int4 export); for plain ORT, `OrtCreateEnv` + load a small embedding `.onnx`. Confirm no missing-symbol/dlopen errors.
- [ ] **Step 4: Commit.**
```bash
git add docs/research/spikes/S3-ffigen.md packages/_onnx_ffigen_spike
git commit -m "docs(spike): ffigen bindings + host dlopen smoke for ORT-GenAI and plain ORT C APIs"
```
**STOP/escalate if:** ffigen cannot produce usable bindings or the host dlopen smoke fails irrecoverably.

---

## Phase A — Embedder package `flutter_gemma_onnx_embeddings` (all 6 platforms, lowest risk)

> Ships standalone value. Plain ORT, single-shot `session.run`. Web via onnxruntime-web. Each task ends green-testable.

### Task A1: Scaffold the embedder package + workspace wiring

**Files:**
- Create: `packages/flutter_gemma_onnx_embeddings/pubspec.yaml`, `.../lib/flutter_gemma_onnx_embeddings.dart`, `.../analysis_options.yaml`, `.../README.md`, `.../CHANGELOG.md`, `.../LICENSE`, `.../test/onnx_embedding_backend_test.dart`
- Modify: `pubspec.yaml` (root — add `packages/flutter_gemma_onnx_embeddings` to `workspace:`)

**Interfaces:**
- Produces: `OnnxEmbeddingBackend` class (`name == 'ONNX Embedding'`, `priority == 0`) exported from the package entrypoint, implementing `EmbeddingBackendProvider`.

- [ ] **Step 1: Read the contract + a sibling.** Read `packages/flutter_gemma/lib/core/registry/embedding_backend_provider.dart` and `packages/flutter_gemma_embeddings/pubspec.yaml` to mirror structure. Read `packages/flutter_gemma/lib/core/model_management/model_specs.dart` to learn the exact `EmbeddingModelSpec` field names (modelPath/tokenizerPath accessors).
- [ ] **Step 2: Write the identity test (failing).**
```dart
// test/onnx_embedding_backend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';

void main() {
  test('OnnxEmbeddingBackend has stable identity', () {
    const b = OnnxEmbeddingBackend();
    expect(b.name, 'ONNX Embedding');
    expect(b.priority, 0);
  });
}
```
- [ ] **Step 3: Run → FAIL** (`flutter test test/onnx_embedding_backend_test.dart` → `OnnxEmbeddingBackend` undefined).
- [ ] **Step 4: Write pubspec + minimal backend.** pubspec mirrors the embeddings sibling (resolution: workspace; deps: `flutter_gemma: ^1.0.1`, `ffi`, `flutter_onnxruntime` for the embedder client; SDK/Flutter floors; repo URLs). Backend:
```dart
// lib/flutter_gemma_onnx_embeddings.dart
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart' show EmbeddingModelSpec;

class OnnxEmbeddingBackend implements EmbeddingBackendProvider {
  const OnnxEmbeddingBackend();
  @override
  String get name => 'ONNX Embedding';
  @override
  int get priority => 0;
  @override
  bool canHandle(EmbeddingModelSpec spec) =>
      spec.modelPath.endsWith('.onnx') || spec.modelPath.endsWith('.ort');
  @override
  Future<EmbeddingModel> createModel(EmbeddingModelSpec spec, RuntimeConfig config) {
    throw UnimplementedError('Implemented in Task A3');
  }
}
```
- [ ] **Step 5: Add to root workspace + bootstrap.** Add `- packages/flutter_gemma_onnx_embeddings` to root `pubspec.yaml` `workspace:`; run `dart pub get` from worktree root → `Got dependencies!`.
- [ ] **Step 6: Run → PASS** (`flutter test test/onnx_embedding_backend_test.dart` → identity test passes).
- [ ] **Step 7: Commit.**
```bash
git add packages/flutter_gemma_onnx_embeddings pubspec.yaml pubspec.lock
git commit -m "feat(onnx-embeddings): scaffold package + OnnxEmbeddingBackend identity"
```

### Task A2: Native-asset hook for the plain-ORT embedder bundle

**TASK A2 REMOVED** — the embedder needs no custom native-asset hook. `flutter_onnxruntime: ^1.8.0` already delivers libonnxruntime on all platforms (CocoaPods on iOS/macOS, Gradle/Maven on Android, CMake on Linux/Windows). A3 uses `flutter_onnxruntime`'s Dart `session.run` API — not raw FFI. A custom hook would cause double-delivery and version conflicts of libonnxruntime. (Decided after the A2 architecture review, 2026-06-21.)

The native-asset hook lives only on the GENERATOR package (Phase C / Task C2), which binds the ORT-GenAI C API directly via `dart:ffi` and requires fetching TWO archives.

### Task A3: Embedder client — tokenize → session.run → pool → normalize (native)

**Files:**
- Create: `.../lib/src/onnx_embedding_model.dart`, `.../lib/src/ort_client.dart` (FFI/flutter_onnxruntime wrapper), `.../lib/src/tokenizer.dart` (reuse the existing Dart SentencePiece path — read how `flutter_gemma_embeddings` tokenizes)
- Test: `.../test/onnx_embedding_model_test.dart` (fakes — no native)

**Interfaces:**
- Consumes: `OnnxEmbeddingBackend.createModel` (Task A1), the hook lib (A2).
- Produces: `OnnxEmbeddingModel implements EmbeddingModel` with `Future<List<double>> generateEmbedding(String, {TaskType})`, `Future<List<List<double>>> generateEmbeddings(List<String>, {TaskType})`, `Future<int> getDimension()`, `addCloseListener`, `close()`.

- [ ] **Step 1: Read the embedding contract** (`EmbeddingModel` in `flutter_gemma_interface.dart`) and how `flutter_gemma_embeddings` does tokenize→pool→L2-normalize, to match output semantics (mean-pooling, L2-normalize → dot product = cosine).
- [ ] **Step 2: Write fake-backed unit tests (failing).** A `_FakeOrtClient` returns a fixed token-embedding tensor; assert `generateEmbedding` mean-pools + L2-normalizes (vector norm ≈ 1.0), `generateEmbeddings` batches, `getDimension` returns the model's hidden size, `close()` is idempotent. (No dlopen — pure Dart, mirror litertlm fakes.)
- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement** `OnnxEmbeddingModel` + `OrtClient` (delegating real session.run to `flutter_onnxruntime`, injected so tests use the fake) + tokenizer reuse. Wire `OnnxEmbeddingBackend.createModel` to build it from `spec.modelPath`/`spec.tokenizerPath` + `config`.
- [ ] **Step 5: Run → PASS** (`flutter test`).
- [ ] **Step 6: Commit.**
```bash
git add packages/flutter_gemma_onnx_embeddings/lib packages/flutter_gemma_onnx_embeddings/test/onnx_embedding_model_test.dart
git commit -m "feat(onnx-embeddings): embedding model (tokenize/pool/normalize) with fake-tested logic"
```

### Task A4: Web embedder via onnxruntime-web (js-interop)

**Files:**
- Create: `.../lib/src/ort_client_web.dart` (js-interop to onnxruntime-web), `.../lib/src/ort_client_stub.dart` + conditional import in `ort_client.dart`
- Modify: `.../web/` assets if onnxruntime-web wasm must be served; `.../README.md` (web setup)
- Test: `.../test/ort_client_web_compile_test.dart` (compile-only contract)

**Interfaces:**
- Produces: a web `OrtClient` implementation with the SAME signature as native, swapped via conditional import on `dart.library.js_interop`.

- [ ] **Step 1: Mirror the litertlm web pattern.** Read how `flutter_gemma_litertlm` does its web conditional import + stub (the 0.15.0 stub-drift lesson). Define the `OrtClient` abstract interface so native and web stubs share an identical signature (prevents dart2js "No named parameter" drift).
- [ ] **Step 2: Implement `ort_client_web.dart`** via `package:web` / `dart:js_interop` against onnxruntime-web (`ort.InferenceSession.create`, `session.run`). Add the conditional import `ort_client_io.dart if (dart.library.js_interop) ort_client_web.dart`.
- [ ] **Step 3: Compile gate.** From `packages/flutter_gemma/example`, `flutter build web --no-tree-shake-icons` with the embedder wired → must compile (this is the drift gate; analyze alone won't catch it).
- [ ] **Step 4: Commit.**
```bash
git add packages/flutter_gemma_onnx_embeddings/lib packages/flutter_gemma_onnx_embeddings/web packages/flutter_gemma_onnx_embeddings/README.md
git commit -m "feat(onnx-embeddings): web embedder via onnxruntime-web with stub-safe conditional import"
```

### Task A5: Integration tests for the embedder on all 6 platforms

**Files:**
- Create: `packages/flutter_gemma/example/integration_test/onnx_embedding_test.dart` (universal native), `.../onnx_embedding_web_test.dart` (`@TestOn('chrome')`)
- Modify: `packages/flutter_gemma/example/integration_test/inference_test_helpers.dart` (register the ONNX embedder), `packages/flutter_gemma/example/pubspec.yaml` (add `flutter_gemma_onnx_embeddings` path dep + override), `example/scripts/download_test_models.sh` (add the EmbeddingGemma ONNX model)

**Interfaces:**
- Consumes: A1–A4 (the working embedder).
- Produces: integration tests that install `onnx-community/embeddinggemma-300m-ONNX`, embed two sentences, and assert cosine similarity (similar > different) on each platform.

- [ ] **Step 1: Add the test model.** Extend `download_test_models.sh` to fetch `onnx-community/embeddinggemma-300m-ONNX` (model.onnx + model.onnx_data + tokenizer) into the per-platform model dirs (Android `/data/local/tmp/...` via adb, desktop `~/models`, etc. — follow the litertlm provisioning table).
- [ ] **Step 2: Write the universal native test** (mirrors `litertlm_ffi_test.dart` structure): register `OnnxEmbeddingBackend`, install the model from the platform path, `ai.embed` two semantically-similar + one different sentence, assert `cosine(similar) > cosine(different)` and `embedding.length == dimension`. Platform-conditional model paths (macOS/iOS/Android/Linux/Windows).
- [ ] **Step 3: Write the web test** (`@TestOn('chrome')`, mirrors `litertlm_web_test.dart`): same assertions, model fetched from HF URL, onnxruntime-web WASM.
- [ ] **Step 4: Run per platform you have locally** (per the test-pattern doc). On the dev host (macOS): `cd packages/flutter_gemma/example && flutter test integration_test/onnx_embedding_test.dart -d macos` → PASS. Web: `chromedriver --port=4444 & flutter drive --driver=test_driver/integration_test.dart --target=integration_test/onnx_embedding_web_test.dart -d chrome` → PASS. (Android/iOS/Linux/Windows run in CI Phase D.)
- [ ] **Step 5: Commit.**
```bash
git add packages/flutter_gemma/example/integration_test/onnx_embedding_test.dart packages/flutter_gemma/example/integration_test/onnx_embedding_web_test.dart packages/flutter_gemma/example/integration_test/inference_test_helpers.dart packages/flutter_gemma/example/pubspec.yaml example/scripts/download_test_models.sh
git commit -m "test(onnx-embeddings): integration tests (cosine similarity) on native + web"
```

### Task A6: Embedder docs + dry-run

**Files:** Modify `.../README.md`, `.../CHANGELOG.md`; site `website/content/docs/packages.md` + a footer link (per the website code-block-dart-only rule).

- [ ] **Step 1: README** — usage (register `OnnxEmbeddingBackend` in `FlutterGemma.initialize(embeddingBackends: [...])`), supported model (EmbeddingGemma ONNX), platform table (all 6), web setup. Use only ` ```dart ` / bare fences (website highlighter has no yaml grammar).
- [ ] **Step 2: CHANGELOG** `0.1.0` entry.
- [ ] **Step 3: dry-run** `cd packages/flutter_gemma_onnx_embeddings && dart pub publish --dry-run` → 0 warnings (commit first so git-state warning clears).
- [ ] **Step 4: Commit.**
```bash
git add packages/flutter_gemma_onnx_embeddings/README.md packages/flutter_gemma_onnx_embeddings/CHANGELOG.md website/content/docs/packages.md website/lib/landing/sections/site_footer.dart
git commit -m "docs(onnx-embeddings): README, CHANGELOG, site packages entry"
```

---

## Phase C — Generator package `flutter_gemma_onnx` (5 native platforms, ORT-GenAI)

> Higher risk. Gated on S1–S3. iOS gated on S2's verdict. No web.

### Task C1: Scaffold the generator package + workspace wiring

**Files:** Create `packages/flutter_gemma_onnx/{pubspec.yaml, lib/flutter_gemma_onnx.dart, analysis_options.yaml, README.md, CHANGELOG.md, LICENSE, test/onnx_engine_test.dart}`; Modify root `pubspec.yaml`.

**Interfaces:** Produces `OnnxEngine implements InferenceEngineProvider` (`name == 'ONNX'`, `priority == 0`, `canHandle` true for `.onnx`/`.ort`).

- [ ] **Step 1: Identity test (failing)** — mirror litertlm's `litert_lm_engine_test.dart`: `const OnnxEngine()`, `engine.name == 'ONNX'`, `engine.priority == 0`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: pubspec + minimal engine** (resolution: workspace; deps `flutter_gemma: ^1.0.1`, `ffi`; `ffigen` dev-dep; SDK/Flutter floors; repo URLs). `canHandle` per global constraint; `createModel` throws `UnimplementedError('Task C3')`.
- [ ] **Step 4: Root workspace + bootstrap** → `Got dependencies!`.
- [ ] **Step 5: Run → PASS.**
- [ ] **Step 6: Commit** `feat(onnx): scaffold package + OnnxEngine identity`.

### Task C2: Generator native-asset hook (two-archive: ORT-GenAI + plain ORT)

**Files:** Create `packages/flutter_gemma_onnx/hook/build.dart`; Test `.../test/hook_config_test.dart`.

**Interfaces:** Consumes S2's desktop two-archive recipe + S1's plain-ORT table. Produces a hook registering `libonnxruntime-genai.*` + `libonnxruntime.*` as CodeAssets on 4-5 native platforms (no web), each SHA-verified.

- [ ] **Step 1: Adapt the litertlm hook for TWO bundles.** Namespace `onnx_genai`; fetch + verify both the genai archive and the plain-ORT archive per platform; register both libs as companions (`mainLibName: 'onnxruntime-genai'`, `companions: ['onnxruntime']`). iOS only if S2 said feasible (else exclude iOS in the platform guard + note in README).
- [ ] **Step 2: Config test (failing → pass)** — assert the const config (namespace, both archive prefixes, companion list).
- [ ] **Step 3: Host fetch smoke** — `flutter build macos --debug` from example with a generator consumer → both dylibs land + verify + the loader resolves `libonnxruntime-genai`'s `NEEDED libonnxruntime`.
- [ ] **Step 4: Commit** `feat(onnx): two-archive native hook (ORT-GenAI + plain ORT), SHA-verified`.

### Task C3: ffigen bindings + FFI client (generate loop, KV-cache, sampling)

**Files:** Create `.../ffigen.yaml`, `.../lib/src/ort_genai_bindings.g.dart` (generated), `.../lib/src/ort_genai_client.dart`, `.../lib/src/onnx_inference_model.dart`; Tests `.../test/ffi/*` (fakes).

**Interfaces:** Consumes S3's ffigen config + C2's libs. Produces `OnnxInferenceModel implements InferenceModel` (createChat/createSession returning a chat/session that streams tokens via the ORT-GenAI generate loop), with the FFI client behind an injectable interface so unit tests use fakes.

- [ ] **Step 1: Generate bindings** from `ort_genai_c.h` (pinned version from S3) via `dart run ffigen`. Commit the generated `.g.dart`.
- [ ] **Step 2: Write fake-backed FFI unit tests (failing)** — mirror litertlm `test/ffi/`: a `_FakeGenAiClient` scripts token chunks; assert streaming order, `stopGeneration` cancels, session isolation, `close()` idempotent + fires `onClose`, cap check throws `StateError` before native. NO dlopen.
- [ ] **Step 3: Run → FAIL.**
- [ ] **Step 4: Implement** `OrtGenAiClient` (wraps the generated bindings: `OgaCreateModel` → `OgaCreateTokenizer` → `OgaCreateGeneratorParams` → token-by-token `OgaGenerator_GenerateNextToken`/`GetNextTokens`) + `OnnxInferenceModel` mapping `RuntimeConfig` (maxTokens, sampling) to genai params. Wire `OnnxEngine.createModel`.
- [ ] **Step 5: Run → PASS.**
- [ ] **Step 6: Commit** `feat(onnx): ffigen bindings + ORT-GenAI FFI client with fake-tested generate loop`.

### Task C4: Isolate / serialized-queue integration

**Files:** Modify `.../lib/src/onnx_inference_model.dart`; Test `.../test/ffi/serialization_test.dart`.

**Interfaces:** Produces the same serialized-call discipline the core expects (one native call at a time), mirroring litertlm's session model.

- [ ] **Step 1: Read litertlm's session/queue model** (`ffi_inference_model.dart`, multi-session test) to match the concurrency contract (the core serializes native calls; `maxConcurrentSessions` cap).
- [ ] **Step 2: Fake test (failing → pass)** — concurrent `generate` calls are serialized; `openSession` honors `maxConcurrentSessions` cap (throws on cap=0).
- [ ] **Step 3: Implement** the queue/lock around the FFI generate loop (future-chain lock like the core model action), optionally off-main-isolate if S3 found it safe.
- [ ] **Step 4: Commit** `feat(onnx): serialized native-call queue + session cap`.

### Task C5: Integration tests for the generator (5 native platforms)

**Files:** Create `packages/flutter_gemma/example/integration_test/onnx_gen_test.dart` (universal native, no web); Modify `inference_test_helpers.dart` (register `OnnxEngine`), `example/pubspec.yaml`, `download_test_models.sh` (add a small Gemma/Phi ONNX-GenAI int4 model).

**Interfaces:** Consumes C1–C4. Produces an integration test that installs a small ORT-GenAI model, generates from a prompt, asserts non-empty streamed text + token count, on each native platform.

- [ ] **Step 1: Add the test model** — a small ONNX-GenAI int4 export (e.g. `onnxruntime/Gemma-3-... cpu-int4` per the research) to the provisioning script + per-platform dirs.
- [ ] **Step 2: Universal native test** (mirror `litertlm_ffi_test.dart`): register `OnnxEngine`, install model, `ai.generate(prompt)` + `ai.generateStream`, assert non-empty text, streaming yields >1 chunk, `stopGeneration` works. Platform-conditional paths; NO web (`@TestOn('!chrome')` or skip on web).
- [ ] **Step 3: Run on host (macOS)** → `flutter test integration_test/onnx_gen_test.dart -d macos` → PASS. (Android/iOS/Linux/Windows in CI.)
- [ ] **Step 4: Commit** `test(onnx): generation integration test on native platforms`.

### Task C6: Generator docs + dry-run

**Files:** Modify `.../README.md`, `.../CHANGELOG.md`, site `packages.md`/`genkit.md`(if relevant)/footer.

- [ ] **Step 1: README** — register `OnnxEngine` in `inferenceEngines:`, supported models (Gemma/Llama/Phi ONNX-GenAI), **platform table (5 native, NO web)**, model-builder note (ORT GenAI model builder / HF ONNX exports), CPU-only-on-mobile note. ` ```dart `/bare fences only.
- [ ] **Step 2: CHANGELOG** `0.1.0`.
- [ ] **Step 3: dry-run** → 0 warnings.
- [ ] **Step 4: Commit** `docs(onnx): README, CHANGELOG, site entry`.

---

## Phase D — Per-platform integration verification (the project's REAL mechanism)

> The project does NOT use a GitHub integration matrix. Per `docs/TESTING.md`, integration tests run via `flutter test integration_test/<file>.dart -d <device>` on per-platform device sources: local (macOS/iOS-sim/web), Firebase Test Lab (Android), and GCloud VMs (Linux `flutter-gemma-linux` with `xvfb-run -a`; Windows `flutter-gemma-gpu` via a Scheduled-Task pattern because interactive `flutter test` dies when the IAP tunnel rotates). This phase runs the ONNX integration tests through that SAME mechanism and records a "N/N PASS" gate per platform, mirroring litertlm's 18-test release gate.
>
> **LOOP AUTONOMY BOUNDARY (read before running in a loop):**
> - **Loop runs AND verifies locally (no escalation):** macOS (`-d macos`), web (`-d chrome`), iOS-simulator (`-d <sim-uuid>` from `xcrun simctl`). The embedder reaches all three; the generator reaches macOS + iOS-sim (IF the ORT-GenAI/ORT xcframework has a simulator slice — confirmed in S2; else iOS-sim is escalated).
> - **Loop AUTHORS tests + run-scripts but ESCALATES execution (needs your access):** Android via **Firebase Test Lab** (`gcloud auth` + `firebase` project), Linux/Windows via **GCloud VMs** (`gcloud compute ssh flutter-gemma-linux/-gpu`, IAP tunnel). The loop cannot authenticate to your GCloud/FTL — it stops at these and hands you the exact command to run (or you provide creds via `! gcloud auth login`).
> - iOS **device** (real iPhone) codesign + `dart pub publish` are always human steps.

### Task D1: Embedder integration gate — local platforms (macOS, web, iOS-sim)

**Files:** none new (runs A5's tests); record results in `docs/research/spikes/D1-embedder-gate.md`.

**Interfaces:** Consumes A5. Produces a recorded PASS on the 3 locally-available platforms.

- [ ] **Step 1: macOS.** `cd packages/flutter_gemma/example && flutter test integration_test/onnx_embedding_test.dart -d macos` → all assertions PASS. (Hook fetches the plain-ORT macOS dylib; model from `~/models`.)
- [ ] **Step 2: Web.** `chromedriver --port=4444 &` then `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/onnx_embedding_web_test.dart -d chrome` → PASS (onnxruntime-web WASM).
- [ ] **Step 3: iOS-simulator.** Boot a sim (`xcrun simctl boot "iPhone 16"`), `flutter test integration_test/onnx_embedding_test.dart -d <sim-uuid>` → PASS. (Requires the plain-ORT iOS xcframework to have a simulator slice — verified in S1/S2; if missing, record SKIP + escalate.)
- [ ] **Step 4: Record + commit** the gate doc with the 3 PASS/SKIP results.
```bash
git add docs/research/spikes/D1-embedder-gate.md
git commit -m "test(onnx-embeddings): local integration gate (macOS, web, iOS-sim) recorded"
```

### Task D2: Generator integration gate — local platforms (macOS, iOS-sim)

**Files:** none new (runs C5's test); record in `docs/research/spikes/D2-generator-gate.md`.

**Interfaces:** Consumes C5. Produces recorded PASS on macOS (+ iOS-sim if S2 confirmed a sim slice).

- [ ] **Step 1: macOS.** `cd packages/flutter_gemma/example && flutter test integration_test/onnx_gen_test.dart -d macos` → generates non-empty streamed text, PASS. (Hook fetches BOTH ORT-GenAI + plain-ORT macOS dylibs.)
- [ ] **Step 2: iOS-simulator** (only if S2 confirmed the ORT-GenAI xcframework has a sim slice; else record SKIP + escalate to v2). `flutter test integration_test/onnx_gen_test.dart -d <sim-uuid>` → PASS or SKIP.
- [ ] **Step 3: Record + commit.**
```bash
git add docs/research/spikes/D2-generator-gate.md
git commit -m "test(onnx): local generation gate (macOS, iOS-sim) recorded"
```

### Task D3: Remote-platform run scripts (Android FTL + Linux/Windows GCloud VMs) — authored, execution escalated

**Files:** Create `packages/flutter_gemma/example/scripts/run_onnx_integration_<platform>.sh` for android-ftl, linux-gcloud, windows-gcloud; doc `docs/research/spikes/D3-remote-runs.md`.

**Interfaces:** Consumes A5/C5. Produces ready-to-run scripts mirroring the litertlm remote-run pattern (from `docs/TESTING.md`), and a documented hand-off for the human/creds.

- [ ] **Step 1: Android FTL script.** `run_onnx_integration_android-ftl.sh`: build the example debug + test APK (`flutter build apk --debug` + the `gradlew app:assembleAndroidTest`), then `gcloud firebase test android run` with the ONNX integration test, results to a GCS bucket. Mirror any existing FTL invocation if present in repo history; otherwise follow the standard `gcloud firebase test android run --type instrumentation` form.
- [ ] **Step 2: Linux GCloud VM script.** `run_onnx_integration_linux-gcloud.sh`: `gcloud compute ssh flutter-gemma-linux --zone us-central1-a --project krups-develop --command "cd … && xvfb-run -a flutter test integration_test/onnx_*_test.dart -d linux"` (per `docs/TESTING.md`). Push the model to the VM's `~/models` first.
- [ ] **Step 3: Windows GCloud VM script.** `run_onnx_integration_windows-gcloud.sh`: follow the Scheduled-Task pattern documented in `docs/TESTING.md` (interactive `flutter test` dies on IAP-tunnel rotation) — register a scheduled task on `flutter-gemma-gpu` that runs the ONNX integration test and writes results to a file the script polls.
- [ ] **Step 4: ESCALATE execution.** A loop STOPS here: it has authored the scripts but cannot authenticate to GCloud/FTL. Output the three exact commands for the human to run (or request `! gcloud auth login`). Record expected "N/N PASS" criteria in the doc.
- [ ] **Step 5: Commit the scripts + doc.**
```bash
git add packages/flutter_gemma/example/scripts/run_onnx_integration_*.sh docs/research/spikes/D3-remote-runs.md
git commit -m "test(onnx): remote-platform integration run scripts (Android FTL, Linux/Windows GCloud)"
```

### Task D4: Wire ONNX packages into melos + release pre-flight (TESTING.md gate)

**Files:** Modify root `pubspec.yaml` (melos already covers `test/` dirs via `--dir-exists=test`); update `.claude/skills/release/SKILL.md` and `docs/TESTING.md` to add the ONNX integration gate (analogous to the litertlm 18-test gate) + `dart pub publish --dry-run` for both new packages.

- [ ] **Step 1: Verify melos coverage** — `melos run analyze` + `melos run test` include both ONNX packages → green.
- [ ] **Step 2: Extend `docs/TESTING.md`** with an "ONNX integration gate" section: the embedder gate (`onnx_embedding_test.dart` N/N on macOS/iOS/Android/Linux/Windows + web) and generator gate (`onnx_gen_test.dart` N/N on the 5 native), referencing the D1–D3 run mechanisms. Extend the release skill with ONNX compile-sanity (`flutter build apk/ios/macos/web` from example with ONNX wired) + dry-run for both packages.
- [ ] **Step 3: Commit** `chore(onnx): wire packages into melos + TESTING.md/release gate`.

### Task D3: Wire ONNX packages into melos + release pre-flight

**Files:** Modify root `pubspec.yaml` (ensure `melos run analyze`/`test` cover the new packages — they already do via `--dir-exists=test`); update `.claude/skills/release/SKILL.md` to add the ONNX example build-sanity targets + `dart pub publish --dry-run` for both new packages.

- [ ] **Step 1: Verify melos coverage** — `melos run analyze` + `melos run test` include both ONNX packages (they have `test/` dirs). Run both → green.
- [ ] **Step 2: Extend the release skill** with the ONNX compile-sanity (`flutter build apk/ios/macos/web` from example with ONNX wired) + dry-run for both packages.
- [ ] **Step 3: Commit** `chore(onnx): wire packages into melos + release pre-flight`.

---

## Phase E — Finalize

### Task E1: Full verification + PR

- [ ] **Step 1: Whole-workspace gate.** `dart pub get` (clean resolve) → `melos run analyze` (no issues) → `melos run test` (all packages green, incl. both ONNX) → `dart pub publish --dry-run` for both ONNX packages (0 warnings).
- [ ] **Step 2: Local integration smoke** on the dev host: embedder `-d macos` + web, generator `-d macos` → PASS.
- [ ] **Step 3: Push + PR** into main with a body summarizing the two packages, the per-platform test matrix, the CPU-only-mobile + no-web-generation constraints, and the deferred items (mobile GPU EPs, iOS-generation if S2 deferred it). Do NOT merge (per-PR approval).

---

## Deferred (explicitly out of scope for v1)
- Mobile/desktop GPU execution providers (NNAPI/CoreML/QNN on mobile; CUDA/DirectML opt-in bundles on Win/Linux-x64).
- Web generation (impossible — ORT-GenAI has no WASM build).
- iOS generation IF S2 finds the codesign defect unresolved (ship generator as Android+desktop, add iOS in v2).
- Genkit-level ONNX wiring (the genkit_flutter_gemma bridge already works against any registered engine/backend — no ONNX-specific change needed).
