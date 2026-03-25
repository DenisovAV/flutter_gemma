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

From the diff, detect which platforms/areas are affected:
- `android/` — Android native (Kotlin, engines, MediaPipe/LiteRT-LM)
- `ios/` — iOS native (Swift, MediaPipe, embeddings)
- `lib/web/` or `web/` — Web platform (JS interop, WASM)
- `lib/desktop/` or `litertlm-server/` — Desktop (gRPC, Kotlin JVM)
- `lib/core/` — Core abstractions (ModelSource, handlers, DI)
- `example/integration_test/` — E2E tests
- `macos/scripts/` or `windows/scripts/` — Build/setup scripts

### Step 3: Launch ALL agents in parallel

Launch all 10 agents simultaneously using the Agent tool. Each agent gets:
- The full diff (or list of changed files)
- The affected platform(s)
- Its specific review checklist (below)

**CRITICAL: All agents MUST run in parallel via a single message with multiple Agent tool calls.**

---

## Agent Specifications

### Agent 1: Platform — Android Engine Layer

**subagent_type:** `general-purpose`

**Prompt template:**
```
You are reviewing the Android engine layer for flutter_gemma — a Flutter plugin for on-device AI inference.

Review these areas if changed:
- android/src/main/kotlin/dev/flutterberlin/flutter_gemma/engines/ (InferenceEngine, InferenceSession, EngineFactory, EngineConfig)
- android/src/main/kotlin/dev/flutterberlin/flutter_gemma/engines/mediapipe/ (MediaPipeEngine, MediaPipeSession)
- android/src/main/kotlin/dev/flutterberlin/flutter_gemma/engines/litertlm/ (LiteRtLmEngine, LiteRtLmSession)
- android/src/main/kotlin/dev/flutterberlin/flutter_gemma/FlutterGemmaPlugin.kt
- android/build.gradle

CHECKLIST:
1. STRATEGY PATTERN: InferenceEngine/InferenceSession interfaces correctly implemented by both MediaPipe and LiteRT-LM adapters
2. ENGINE SELECTION: EngineFactory selects correct engine by file extension (.task/.bin → MediaPipe, .litertlm → LiteRT-LM)
3. THREAD SAFETY: Coroutine scope usage, synchronized blocks for prompt accumulation in LiteRtLmSession
4. CANCEL GENERATION: cancelGeneration() correctly calls conversation.cancelProcess() (LiteRT-LM) or SDK cancel (MediaPipe). Error handling around cancel — should not throw to caller
5. CHUNK BUFFERING: LiteRtLmSession buffers addQueryChunk() in StringBuilder, sends complete message on generateResponse(). Thread-safe accumulation with promptLock
6. FLOW MANAGEMENT: SharedFlow for partial results and errors. tryEmit() usage — check for dropped emissions
7. MULTIMODAL: addImage()/addAudio() store bytes correctly. Content.ImageBytes/Content.AudioBytes built properly in buildAndConsumeMessage()
8. CAPABILITY REPORTING: EngineCapabilities reflects actual runtime state (vision/audio depend on backend config)
9. DEPENDENCY VERSIONS: MediaPipe tasks-genai and litertlm-android versions consistent with CLAUDE.md

Report findings as: CRITICAL / IMPORTANT / MINOR with file:line references.
```

### Agent 2: Platform — iOS Native

**subagent_type:** `general-purpose`

**Prompt template:**
```
You are reviewing the iOS native layer for flutter_gemma — a Flutter plugin for on-device AI inference.

Review these areas if changed:
- ios/Classes/ (Swift plugin, MediaPipe integration, embedding model)
- ios/flutter_gemma.podspec
- example/ios/Podfile, Podfile.lock

CHECKLIST:
1. MEDIAPIPE INTEGRATION: LlmInference setup, session management, response generation
2. EMBEDDING MODEL: BPETokenizer.swift and UnigramTokenizer.swift — correct tokenization, auto-detect via model.type in tokenizer.json
3. MEMORY MANAGEMENT: Sessions and models properly closed/released. No retain cycles
4. PLATFORM CONSTRAINTS: iOS 16.0 minimum. No SentencePiece C++ (conflicts with TFLite protobuf). No MediaPipeTasksText (doesn't exist for iOS)
5. COCOAPODS: Podspec dependencies correct. use_frameworks! :linkage => :static
6. CANCEL GENERATION: If implemented, verify SDK method exists and error handling
7. MULTIMODAL: Vision support on physical devices only (broken on Apple Silicon simulator)

Report findings as: CRITICAL / IMPORTANT / MINOR with file:line references.
```

### Agent 3: Platform — Web

**subagent_type:** `general-purpose`

**Prompt template:**
```
You are reviewing the Web platform layer for flutter_gemma — a Flutter plugin for on-device AI inference.

Review these areas if changed:
- lib/web/flutter_gemma_web.dart (WebInferenceModel, WebModelSession)
- lib/web/llm_inference_web.dart (JS interop)
- web/rag/ (LiteRT embeddings JS, SQLite vector store)
- example/web/index.html (MediaPipe CDN)

CHECKLIST:
1. JS INTEROP: @JS() annotations correct. LlmInference, FilesetResolver properly wrapped
2. MEDIAPIPE CDN: Version pinned (not @latest). Consistent across index.html and Dart code
3. SESSION LIFECYCLE: _initCompleter handling — reset on failure? Multiple createSession() calls safe?
4. PROMPT MANAGEMENT: _promptParts accumulation. Cleared after response? Cleared on cancel? Cleared on close?
5. CANCEL GENERATION: llmInference.cancelProcessing() — error handling, stream controller cleanup
6. CACHE MANAGEMENT: enableWebCache flag. InMemoryModelRepository vs SharedPreferencesModelRepository selection. Metadata lifetime matches blob URL lifetime
7. HOT RESTART SAFETY: Cleanup of WASM resources before reinitialization. No "memory access out of bounds"
8. MULTIMODAL: Image/audio bytes handling via JS interop. Content parts array construction

Report findings as: CRITICAL / IMPORTANT / MINOR with file:line references.
```

### Agent 4: Platform — Desktop / gRPC

**subagent_type:** `general-purpose`

**Prompt template:**
```
You are reviewing the Desktop platform (macOS/Windows/Linux) for flutter_gemma — uses LiteRT-LM via Kotlin/JVM with gRPC.

Review these areas if changed:
- lib/desktop/grpc_client.dart (GrpcLiteRtLmClient)
- lib/desktop/desktop_inference_model.dart (DesktopInferenceModel, DesktopInferenceModelSession)
- lib/desktop/server_process_manager.dart (JVM process lifecycle)
- lib/desktop/generated/ (protobuf generated code — don't review style, check API correctness)
- litertlm-server/src/main/kotlin/dev/flutterberlin/litertlm/LiteRtLmServiceImpl.kt
- litertlm-server/src/main/proto/litertlm.proto
- litertlm-server/build.gradle.kts
- macos/scripts/prepare_resources.sh, setup_desktop.sh
- windows/scripts/setup_desktop.ps1

CHECKLIST:
1. PROTO DESIGN: RPC definitions correct. Request/Response messages well-typed. No untyped JSON in proto fields
2. GRPC CLIENT: Channel setup, timeout handling (5min for chat). Error distinction (cancel vs real error)
3. CANCEL GENERATION: CancelGeneration RPC → server → conversation.cancelProcess(). Fire-and-forget OK but document behavior
4. SERVER LIFECYCLE: Initialize/Shutdown RPCs. Mutex usage — no runBlocking inside coroutine context
5. VISION/AUDIO: Image conversion (convertToPng). Audio bytes passthrough. Error handling on conversion failure — NO silent fallbacks
6. BUILD SCRIPTS: JAR_VERSION, JRE_VERSION, checksums. Cache invalidation on version change. Checksum verification on cached files
7. JRE: Azul Zulu (NOT Temurin — causes Jinja template errors). Version consistent across macOS/Windows scripts
8. DEPENDENCIES: litertlm-jvm version, gRPC versions, protobuf versions consistent between build.gradle.kts and generated code

Report findings as: CRITICAL / IMPORTANT / MINOR with file:line references.
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
- Multi-platform plugin: Android (Kotlin + MediaPipe/LiteRT-LM dual engine), iOS (Swift + MediaPipe), Web (JS + MediaPipe WASM), Desktop (Dart + gRPC + Kotlin JVM + LiteRT-LM)
- Engine selection by file extension: .task/.bin → MediaPipe, .litertlm → LiteRT-LM
- ModelSource sealed class: NetworkSource, AssetSource, BundledSource, FileSource
- Installation stores identity (modelType, fileType), runtime accepts config (maxTokens, preferredBackend)
- Error handling: NO silent fallbacks. Throw or return error, never swallow in catch blocks
- No inline string keys — use PreferencesKeys constants
- Desktop uses Azul Zulu JRE (NOT Temurin — causes Jinja template errors)
- iOS: No SentencePiece C++ (protobuf conflict), no MediaPipeTasksText (doesn't exist)

Review steps:
1. Run: gh pr diff {number}
2. Read CLAUDE.md for full project conventions
3. Cross-check: engine selection logic, proto/gRPC consistency, platform-specific limitations

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
