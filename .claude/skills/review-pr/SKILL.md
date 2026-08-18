---
name: review-pr
description: Comprehensive PR review for flutter_gemma. Runs 10 specialized reviewers in parallel (4 platform-specific + 6 general). Use when reviewing PRs or before merging.
user_invocable: true
---

# Flutter Gemma PR Review

Run comprehensive PR review with 10 parallel agents — 4 platform-specific + 6 general-purpose.

## Usage

```
/review-pr 198        # Review PR by number
/review-pr            # Review current branch vs main
```

## Process

### Step 1: Get the diff

**If PR number provided:**
```bash
gh pr view {number} --json title,body,files --jq '.title'
gh pr diff {number} > /tmp/pr-{number}.diff
```

**If no PR number:**
```bash
BRANCH=$(git branch --show-current)
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number')
if [ -n "$PR_NUMBER" ]; then
  gh pr diff "$PR_NUMBER" > /tmp/pr-branch.diff
else
  git diff main...HEAD > /tmp/pr-branch.diff
fi
```

### Step 2: Identify changed areas

This is a **Dart pub workspace monorepo** — all code lives under `packages/<pkg>/`.
From the diff, detect which package(s)/area(s) are affected:

**Packages (`packages/<pkg>/`):**
- `flutter_gemma/` — core: registry, contracts, shells, ModelSource, slim native plugin (its `android/` `ios/` host only the bundled channel)
- `flutter_gemma_litertlm/` — `.litertlm` FFI engine; `native/litert_lm/` build scripts, `lib/src/ffi/`, `hook/build.dart`
- `flutter_gemma_embeddings/` — LiteRT C API embeddings (isolate worker)
- `flutter_gemma_mediapipe/` — `.task` MediaPipe; owns pigeon (`lib/pigeon.g.dart`) + Kotlin/Swift + web JS
- `flutter_gemma_rag_qdrant/` — native RAG (qdrant-edge Rust FFI), `native/qdrant_edge/`
- `flutter_gemma_rag_sqlite/` — sqlite-vec `vec0` KNN on all six platforms; native via `package:sqlite3` FFI, web via `package:sqlite3/wasm.dart` (wa-sqlite was dropped in 1.1.0)
- `flutter_gemma_speech/` — opt-in STT (moonshine / Whisper / Parakeet) + TTS (Matcha / Qwen3 / Inflect) over the LiteRT C API; shares the litertlm bundle
- `flutter_gemma_agent/` — opt-in SKILL.md agent skills over the function-calling loop (no Web)
- `flutter_gemma_builtin_ai/` — OS models: Gemini Nano via ML Kit GenAI (Android, `minSdk 26`), Apple Foundation Models (iOS/macOS, `sharedDarwinSource`). Owns its own pigeon.
- `genkit_flutter_gemma/`, `genkit_hybrid/` — Genkit integration packages (Dart; no native)
- `flutter_gemma/example/` — example app + `integration_test/` E2E

**Native (per package):** `packages/<pkg>/android/`, `ios/`, `windows/`, `native/`, `hook/build.dart`
**Web:** `packages/*/lib/src/web/`, `packages/*/web/` (JS interop, WASM)
**Desktop:** `packages/*/lib/desktop/` + FFI in `flutter_gemma_litertlm`
**Site:** `website/` — Jaspr landing + docs (deployed to fluttergemma.dev; CI `.github/workflows/firebase-hosting-merge.yml`)
**Repo-level:** `.github/workflows/`, `.claude/skills/`, root `pubspec.yaml` (workspace + melos)

### Step 3: Launch ALL agents in parallel

Launch all 10 agents simultaneously using the Agent tool. Each agent gets:
- The full diff (or list of changed files)
- The affected platform(s)
- Its specific review checklist (below)

**CRITICAL: All agents MUST run in parallel via a single message with multiple Agent tool calls.**

---

## Agent Specifications

Every path named in an agent prompt below was verified to exist. If one stops
resolving, that is the finding — fix the skill before running the review, because
an agent pointed at a missing directory returns a clean report.

### Agent 1: Android native

**subagent_type:** `android-architect`

```
You are reviewing the Android native layer of flutter_gemma, a Dart pub workspace
monorepo. Inference itself is NOT in Kotlin — `.litertlm` runs through Dart FFI.
Kotlin exists in exactly three packages; confirm with
`find packages -path '*/android/src/main/kotlin' -name '*.kt'` before you start.

- packages/flutter_gemma/android/.../FlutterGemmaPlugin.kt — SLIM. Hosts only the
  `flutter_gemma_bundled` channel: file ops plus the litertlm NPU
  `getNativeLibraryDir`. If a change adds inference logic here, that is the
  finding.
- packages/flutter_gemma_mediapipe/android/ — the only real engine layer:
  own pigeon (PigeonInterface.g.kt), PlatformServiceImpl, InferenceModel, and
  engines/{InferenceEngine,EngineFactory,InferenceSession,EngineConfig}.kt plus
  engines/mediapipe/. EngineFactory handles `.task`/`.bin`/`.tflite` ONLY — it
  throws on `.litertlm` with a message pointing at the Dart FFI client. That
  throw is correct behaviour, not a bug.
- packages/flutter_gemma_builtin_ai/android/ — ML Kit GenAI / AICore. Declares
  `minSdkVersion 26`; an app on a lower floor fails the manifest merger.

CHECKLIST
1. GRADLE GUARD DUPLICATION: the AGP-9 Kotlin guard must read
   `agpMajor < 9 || !builtInKotlinOn` in ALL THREE android/build.gradle files. A
   version-only `agpMajor < 9` reintroduces #360. Grep all three; a fix in one is
   a half-fix that ships under its own version number.
2. MANIFEST: the `<uses-native-library>` entries (libOpenCL.so, -car, -pixel,
   libvndksupport.so, libcdsprpc.so) live in the CORE plugin manifest and merge
   into consumer apps. libvndksupport is load-bearing for the OpenCL ICD on
   Android 12+ (#324) — removing it degrades GPU to WebGPU and can hard-freeze
   Mali.
3. minSdk: `.litertlm` needs 30 (API-30-only Bionic symbols, #265); builtin_ai
   needs 26; core declares 24. A change to any floor must be consistent with what
   the code actually dlopens.
4. PIGEON: *.g.kt files are generated — never hand-edited. Regenerated from the
   package's own pigeon.dart.
5. NATIVE LIBS: arm64-v8a only for .litertlm/embeddings/vision. A change that
   implies other ABIs ship broken APKs.
6. Coroutine scope, cancellation and prompt accumulation in the MediaPipe session.

Report CRITICAL / IMPORTANT / MINOR with file:line. Skip style nits.
```

### Agent 2: Apple native (iOS + macOS)

**subagent_type:** `swift-reviewer`

```
You are reviewing the Apple native layer of flutter_gemma. Note the layouts
differ per package — verify with `find packages -name '*.swift' | grep -v example`
rather than assuming a single convention:

- packages/flutter_gemma/{ios,macos}/flutter_gemma/Sources/flutter_gemma/ —
  SwiftPM layout (NOT ios/Classes/). Slim plugin: bundled channel only.
- packages/flutter_gemma_mediapipe/ios/Classes/ — classic layout, real engine:
  FlutterGemmaMediaPipePlugin, PlatformServiceImpl, InferenceModel, pigeon .g.swift
- packages/flutter_gemma_builtin_ai/darwin/ — one source tree for iOS + macOS via
  `sharedDarwinSource: true`. Apple Foundation Models.

CHECKLIST
1. Swift 6 concurrency: Sendable conformance, actor isolation, and no
   captured-mutable-state across the pigeon boundary.
2. Podspec versions: four first-party podspecs exist and drift independently —
   core ios, core macos, mediapipe ios, builtin_ai darwin. Each must match its
   OWN package version.
3. iOS floor is 16.0 and it comes from the CORE podspec, so it applies to a
   litertlm-only app too.
4. Entitlements: extended-virtual-addressing and increased-memory-limit for large
   models; on macOS `cs.disable-library-validation` is required for dlopen of the
   ad-hoc-signed companion frameworks — and it must be in BOTH DebugProfile and
   Release entitlements.
5. No `Podfile post_install` symlink step should be reintroduced: those lib*.dylib
   symlinks caused App Store rejection ITMS-90432 (#245). Any bundled dylib needs
   `vtool` minos 13.0 or the upload is rejected (ITMS-90208).
6. Generated pigeon .g.swift is never hand-edited.

Report CRITICAL / IMPORTANT / MINOR with file:line.
```

### Agent 3: Web

**subagent_type:** `general-purpose`

```
You are reviewing the web layer of flutter_gemma. Two independent engines have
web arms, plus embeddings and RAG:

- packages/flutter_gemma_mediapipe/lib/src/web/ — `.task` via @mediapipe/tasks-genai
- packages/flutter_gemma_litertlm/lib/src/web/ — `.litertlm` via @litert-lm/core.
  EARLY PREVIEW: text only. No vision, audio, thinking, function calling or LoRA.
- packages/flutter_gemma_embeddings/ web arm — LiteRT.js, not the C API
- packages/flutter_gemma_rag_sqlite/ — package:sqlite3/wasm.dart + a custom
  sqlite3.wasm with vec0 linked in, which the APP copies into its own web/ dir
- packages/flutter_gemma/lib/web/ — the shared web shells and model source

CHECKLIST
1. CONDITIONAL IMPORT / STUB DRIFT — the highest-value check here. FFI clients
   have `*_stub.dart` counterparts that `flutter analyze` and `flutter test` do
   NOT type-check on the host. Signature drift only surfaces at
   `flutter build web`. If a real signature changed, its stub must change too.
   This is how a web break shipped in 0.15.0 with green analyze and green tests.
2. dart:io / dart:ffi must not reach the web graph. Check the conditional export.
3. The three required web/ assets are not auto-injected — the app copies them:
   cache_api.js (default cacheApi storage), opfs_helper.js (streaming), and
   litert_embeddings.js (web embeddings). A change that needs a new global must
   document the script tag.
4. Storage modes: cacheApi (default, <2GB), streaming (OPFS, large models),
   none. Web is GPU-only — MediaPipe has no web CPU backend.
5. CDN pins: @mediapipe/tasks-genai and @litert-lm/core versions must agree
   between the code and any documented script tag.

Report CRITICAL / IMPORTANT / MINOR with file:line.
```

### Agent 4: Desktop / FFI and native assets

**subagent_type:** `general-purpose`

```
You are reviewing desktop inference and the native-asset pipeline of
flutter_gemma. Desktop is Dart FFI directly into the LiteRT-LM C API — there is
NO JVM, NO gRPC, NO separate server process and no proto layer. If the diff or a
task description mentions any of those, it predates 0.14.0.

- packages/flutter_gemma_litertlm/lib/src/ffi/ — the FFI client, generated
  bindings, and the inference model
- packages/flutter_gemma_litertlm/hook/build.dart — the SOLE hook that owns the
  shared libLiteRtLm bundle. embeddings and speech consume it transitively and
  have no hook of their own.
- packages/flutter_gemma_litertlm/native/litert_lm/ — build_*.sh, patch_c_api.sh,
  stream_proxy.c
- packages/flutter_gemma/{linux,windows}/ — thin plugin registration C++
- packages/flutter_gemma/lib/desktop/ — the registry-dispatch shell

CHECKLIST
1. HOOK CHECKSUMS: a bundle `version:` bump requires all seven per-platform
   SHA256 entries updated, and the same value must appear in the released
   tarball, in checksums_litertlm.txt, and in the hook. A stale txt sent a user
   down the wrong path in #316.
2. NEVER re-upload an existing native-v* tag. tar is not reproducible, so the
   published SHA256 can never be recovered — it breaks every user already on a
   plugin version referencing that tag.
3. windowsExtraLibs / androidExtraLibs and the CI allow-list are ONE SET IN TWO
   PLACES. A name staged by CI but absent from the hook extracts to the cache and
   is never bundled — that is how 78.8 MB of the Intel NPU stack went missing at
   v0.16.0 while every CI assertion passed.
4. Bazel `--define` names rot silently: Bazel accepts an unknown define and
   builds the default. Grep the tree being built before trusting one.
5. stream_proxy.c probes the callback ABI at runtime via dlsym/GetProcAddress
   because v0.15.0 changed the shape with no version symbol. Do not replace that
   with a compile-time branch.
6. `stage()` in the hook is Apple-only on purpose (an Xcode directoryTreeSignature
   cycle); staging on Windows splits companion DLLs and hangs cancel/close.
7. Any claim that a native check "passed" must name the artifact it inspected —
   nm/otool on a missing path prints nothing and reads as success.

Report CRITICAL / IMPORTANT / MINOR with file:line.
```

### Agent 5: Flutter Architect

**subagent_type:** `flutter-architect`

**Prompt:** Review the PR diff for flutter_gemma — a multi-platform Flutter plugin for on-device AI inference. Focus on: plugin architecture (platform channels via Pigeon), SOLID principles, ModelSource sealed class design, handler chain pattern (NetworkSourceHandler, AssetSourceHandler), dependency injection (ServiceRegistry), platform abstraction layer. Check separation of concerns between install-time identity (modelType, fileType) and runtime configuration (maxTokens, preferredBackend). Read CLAUDE.md for project conventions.

### Agent 6: Flutter Coder

**subagent_type:** `flutter-coder`

**Prompt:** Review the changed Dart files in flutter_gemma for code quality. Check: null safety, proper async/await patterns, Stream handling (no leaks, proper cancellation), Message class usage (isUser: true for user messages), PreferencesKeys constants (no inline string keys), proper close()/dispose() in finally blocks, type safety with ModelSource sealed classes. Read CLAUDE.md for coding standards — especially "No Inline String Keys" rule.

### Agent 7: Copilot Review (Second Opinion)

**Run directly via Bash** (not as a subagent — Copilot CLI needs direct shell access):

```bash
copilot -p "You are reviewing PR #{number} for flutter_gemma — a multi-platform Flutter plugin for running Google Gemma AI models locally on Android, iOS, Web, and Desktop.

Key project context:
- A Dart pub workspace monorepo: core flutter_gemma plus opt-in packages under packages/. Core registers no engine; engines and backends are passed to FlutterGemma.initialize().
- .litertlm inference is Dart FFI into the LiteRT-LM C API on every native platform, including desktop. There is NO JVM, NO gRPC, no separate server process and no proto layer — those were removed at 0.14.0. Kotlin exists only in the MediaPipe and builtin_ai packages plus a slim core plugin; MediaPipe never handles .litertlm.
- Engine selection is by the DECLARED ModelFileType via canHandle(spec), NOT by sniffing the file name. installModel defaults fileType to .task, so a .litertlm model must declare it explicitly or it is routed to MediaPipe.
- ModelSource sealed class: NetworkSource, AssetSource, BundledSource, FileSource
- Installation stores identity (modelType, fileType), runtime accepts config (maxTokens, preferredBackend)
- maxTokens is the CONTEXT WINDOW, not the reply length. Below 1024 the .litertlm KV cache allocation fails; the engine clamps up with a warning. To cap a reply use maxOutputTokens on the session.
- Error handling: NO silent fallbacks. Throw or return error, never swallow in catch blocks
- No inline string keys — use PreferencesKeys constants
- Generated files are never hand-edited: pigeon *.g.dart / *.g.kt / *.g.swift, and the ffigen bindings.

Review steps:
1. Run: gh pr diff {number}
2. Read CLAUDE.md for full project conventions
3. Cross-check: engine routing by declared fileType, conditional-import stub drift against the real signatures (analyze does not catch it), and platform-specific limitations

Focus on: bugs, logic errors, security, dead code, silent error swallowing, race conditions in async/streaming code, memory leaks (unclosed sessions/models). Be concise — only report real issues with file:line references. Skip style nits. Categorize as CRITICAL / IMPORTANT / MINOR." \
  --allow-all-tools \
  --allow-all-paths \
  --no-auto-update \
  --output-format text 2>&1
```

If no PR number, detect via: `gh pr list --head $(git branch --show-current) --json number -q '.[0].number'`

**Run this command directly via Bash tool** (timeout: 300000ms). Parse the output and extract findings with severity levels.

### Agent 8: Code Reviewer

**subagent_type:** `pr-review-toolkit:code-reviewer`

**Prompt:** Review the PR for adherence to project guidelines in CLAUDE.md. Focus on recently changed files. Key rules: no inline string keys, proper PreferencesKeys usage, no AI attribution in commits, sessions/models always closed, Message(isUser: true) for user messages.

### Agent 9: Type Design Analyzer

**subagent_type:** `pr-review-toolkit:type-design-analyzer`

**Prompt:** Analyze any new or modified types/interfaces in the PR for encapsulation, invariant expression, and design quality. Focus on: ModelSource sealed class hierarchy, EngineConfig/SessionConfig, InferenceEngine/InferenceSession interfaces, EngineCapabilities, TestModelConfig.

### Agent 10: Silent Failure Hunter

**subagent_type:** `pr-review-toolkit:silent-failure-hunter`

**Prompt:** Check all changed files for silent failures, inadequate error handling, catch blocks that swallow errors, and inappropriate fallback behavior. Key concern areas: image conversion fallbacks (should throw, not return original bytes), tryEmit() that drops errors silently, cancelGeneration() that swallows exceptions, download/checksum verification gaps.

---

## Step 4: Collect and Deduplicate

After all agents complete:

1. Collect all findings from all agents
2. Deduplicate — if two agents report the same issue (same file, same line, same concern), keep the one with better description
3. Categorize by severity: CRITICAL > IMPORTANT > MINOR
4. Group by file path within each severity

## Step 5: Generate Report

Save to `test_reports/pr-reviews/pr-{number}-review.md` (or `pr-branch-{branch}-review.md`):

```markdown
# PR Review: #{number} — {title}

**Branch:** {branch}
**Date:** {date}
**Reviewers:** 10 agents (4 platform-specific + 6 general)
**Platforms affected:** {platforms}

## Critical Issues
{blocking issues that must be fixed before merge}

## Important Issues
{should be fixed, but not blocking}

## Minor Issues
{nice-to-have improvements}

## Passed Checks
{list of checks that passed cleanly}

## Summary
- Critical: X
- Important: Y
- Minor: Z
- Recommendation: APPROVE / REQUEST CHANGES / NEEDS DISCUSSION
```

## Step 6: Output Summary

Print a concise summary to the user:
- Total findings by severity
- Top 3 most important issues
- Recommendation (approve/changes requested)
- Path to full report file
