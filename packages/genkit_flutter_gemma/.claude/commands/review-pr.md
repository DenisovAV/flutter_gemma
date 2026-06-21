# Genkit Flutter Gemma PR Review

Run a comprehensive PR review with 5 parallel agents.

## Usage

```bash
/review-pr 1          # Review PR by number
/review-pr            # Review current branch vs main
```

## Process

### Step 1: Get the diff

Start from the repository root, not the package directory:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
```

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

### Step 2: Launch ALL agents in parallel

Launch all 5 agents simultaneously using the Agent tool. Each agent gets the full diff and its specific checklist.

**CRITICAL: All agents MUST run in parallel via a single message with multiple Agent tool calls.**

---

## Project Context for Agents

**Every agent prompt MUST include the following context block** to prevent false positives:

```text
PROJECT CONTEXT - read this before reporting findings:

1. This is a GENKIT PLUGIN wrapping flutter_gemma. We call flutter_gemma's DART API,
   not native code directly. flutter_gemma itself is a native plugin (MediaPipe/LiteRT),
   but that's its responsibility, not ours. Do NOT report "no error wrapping around
   native calls" - we intentionally let flutter_gemma exceptions propagate with their
   original stack traces.

2. The .g.dart files are MANUALLY MAINTAINED. Report real drift between .dart and
   .g.dart, but fix both files by hand unless the maintainer explicitly asks to
   regenerate. Do not suggest "run build_runner" as the default fix.

3. `fileType` in FlutterGemmaModelConfig is a FORWARD-LOOKING parameter stored for
   identification. flutter_gemma's getActiveModel() doesn't need it - the model is
   already installed. This is NOT a bug.

4. `dispose()` clears the Dart action cache. InferenceModel is a Dart object - native
   resources are managed by flutter_gemma's platform channel, not by us. GC handles
   cleanup. Do NOT report "native resource leak" for dispose().

5. `toolChoice` defaulting to `auto` for unrecognized values is a DESIGN CHOICE, not
   a silent failure. The JSON schema already constrains valid values at the Genkit UI
   level. If an unknown string arrives, `auto` is a safe fallback - same behavior as
   most LLM APIs. The embedder throws on unknown backend because there's no safe default
   for hardware selection. Different domains, different strategies.

6. This is a small plugin (~500 LOC), not a framework. Do NOT suggest creating wrapper
   classes, abstracting one-time operations, or adding layers of indirection. Keep
   suggestions proportional to project scale.

7. Bare `catch (e)` in config parsing (fromJson) is intentional - it catches any
   deserialization error (TypeError, CastError, etc.) and wraps as INVALID_ARGUMENT.
   This is a system boundary where we validate external input. Do NOT suggest catching
   only specific types.
```

---

## Agent Specifications

### Agent 1: Plugin Architecture

**subagent_type:** `general-purpose`

**Prompt template:**

```text
You are reviewing a Genkit Dart plugin (genkit_flutter_gemma) that bridges flutter_gemma for on-device AI inference.

{PROJECT CONTEXT BLOCK}

Read packages/genkit_flutter_gemma/CLAUDE.md for project conventions, then review the diff.

CHECKLIST:
1. PLUGIN CONTRACT: GenkitPlugin interface correctly implemented (list(), resolve()). Action caching in _resolvedActions
2. MODEL ACTION: Future-chain lock correctness - no race conditions. InferenceModel caching logic (invalidation on config change)
3. CONVERTER LAYER: Genkit <-> flutter_gemma type boundary - request_converter, response_converter, tool_converter. No data loss in conversion. Pay special attention to multi-part extraction (parallel tool calls in history must not be dropped)
4. OPTIONS: FlutterGemmaModelOptions and .g.dart in sync. JSON schema matches fields. All new options wired through to createChat()
5. RUNTIME ABSTRACTION: FlutterGemmaRuntime interface - production vs test implementations consistent
6. EMBEDDER: Caching, backend invalidation, document-to-text extraction
7. SEPARATION OF CONCERNS: Converters don't import model/plugin. Model doesn't import plugin

Report findings as: CRITICAL / IMPORTANT / MINOR with file:line references. Only report real issues - not stylistic preferences or over-engineering suggestions.
```

### Agent 2: Code Quality

**subagent_type:** `pr-review-toolkit:code-reviewer`

**Prompt:**

```text
Review the PR for genkit_flutter_gemma - a Genkit Dart plugin wrapping flutter_gemma.

{PROJECT CONTEXT BLOCK}

Focus on recently changed files. Check: null safety, proper async/await patterns, Stream handling (no leaks), const constructors where possible, prefer_single_quotes lint rule, no unused imports. Read packages/genkit_flutter_gemma/CLAUDE.md for project conventions.
```

### Agent 3: Type Design

**subagent_type:** `pr-review-toolkit:type-design-analyzer`

**Prompt:**

```text
Analyze any new or modified types in this PR for genkit_flutter_gemma.

{PROJECT CONTEXT BLOCK}

Focus on: FlutterGemmaModelOptions (schema annotation + generated code), FlutterGemmaModelConfig, FlutterGemmaEmbedderConfig, FlutterGemmaRuntime interface. Check encapsulation, invariant expression, and consistency between .dart and .g.dart files.

KEY CONCERN: The .g.dart files are manually maintained. Check that concrete classes stay in sync with abstract schema classes. If the concrete class does not `implements` the abstract class, flag it as a minor improvement (not critical).
```

### Agent 4: Silent Failure Hunter

**subagent_type:** `pr-review-toolkit:silent-failure-hunter`

**Prompt:**

```text
Check all changed files in genkit_flutter_gemma for silent failures, inadequate error handling, catch blocks that swallow errors, and inappropriate fallback behavior.

{PROJECT CONTEXT BLOCK}

Key areas to check:
- Media resolution (data:/file:/http:) - these error paths matter
- Streaming chunk accumulation - data loss during accumulation is a real bug
- Model caching invalidation - wrong cache key = wrong model reuse
- Request converter extraction - must handle ALL parts, not just first match (e.g. parallel tool calls)
- Response converter - all ModelResponse subtypes must be handled

DO NOT flag:
- toolChoice defaulting to auto (intentional, see context)
- catch(e) in fromJson (intentional system boundary, see context)
- dispose() not releasing "native" resources (not applicable, see context)
- flutter_gemma API errors not being wrapped (not our responsibility, see context)
```

### Agent 5: Test Coverage

**subagent_type:** `pr-review-toolkit:pr-test-analyzer`

**Prompt:**

```text
Review test coverage for genkit_flutter_gemma.

{PROJECT CONTEXT BLOCK}

Check:
- Are all new features tested? (toolChoice, ParallelFunctionCallResponse, latencyMs, ThinkingResponse)
- Are edge cases covered?
- Do fake implementations (FakeRuntime, FakeInferenceModel, FakeInferenceChat, FakeEmbeddingModel) stay in sync with flutter_gemma API?
- Are converter tests comprehensive for new response types?
- Does FakeInferenceModel capture enough createChat() parameters for verification?

Focus on REAL gaps - features that are implemented but have zero test coverage. Don't suggest testing framework internals or obvious paths.
```

---

## Step 3: Collect and Deduplicate

After all agents complete:

1. Collect all findings from all agents
2. **Filter out false positives** using the project context (agents may still report issues covered by the context block - remove these)
3. Deduplicate - same file, same line, same concern -> keep best description
4. Categorize by severity: CRITICAL > IMPORTANT > MINOR
5. Group by file path within each severity

## Step 4: Generate Report

Save to `test_reports/pr-reviews/pr-{number}-review.md`:

```markdown
# PR Review: #{number} - {title}

**Branch:** {branch}
**Date:** {date}
**Reviewers:** 5 agents

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

## Step 5: Output Summary

Print a concise summary to the user:
- Total findings by severity
- Top 3 most important issues
- Recommendation (approve/changes requested)
- Path to full report file
