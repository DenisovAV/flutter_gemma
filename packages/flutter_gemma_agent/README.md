# flutter_gemma_agent

On-device agentic **skills** for [flutter_gemma](https://pub.dev/packages/flutter_gemma).

This opt-in satellite package turns the inference core into an on-device agent:
the model is given a set of *skills* (`SKILL.md`), decides which to invoke via
flutter_gemma's existing function-calling, runs them, and feeds the results back
— fully offline, on all six platforms.

It is reverse-engineered from [google-ai-edge/gallery](https://github.com/google-ai-edge/gallery)
(Apache-2.0) and is **Gallery-compatible**: their `SKILL.md` catalog parses
unmodified, and their JavaScript skills run as-is (the
`window.ai_edge_gallery_get_result` contract is preserved).

## What's in the box

- `Skill` + `SkillType` (`textOnly` / `js` / `intent` / `mcp`) and the
  `parseSkillMd` parser (YAML frontmatter + markdown body).
- `SkillRegistry` — holds available/selected skills and builds the cheap
  name+description discovery string for the system prompt (two-stage discovery).
- `SkillExecutor` probe-chain (mirrors flutter_gemma's engine registry) + sealed
  `SkillResult` (`TextResult` / `ImageResult` / `WidgetResult` / `WebviewResult`
  / `ErrorResult`).
- Concrete executors: `TextSkillExecutor` (0 deps), `JsSkillExecutor`
  (sandboxed `webview_flutter` — the only webview import), `NativeIntentExecutor`
  (whitelisted OS intents behind user/OS confirm), `McpSkillExecutor` (MCP tools
  over Streamable HTTP).
- `AgentLoop` + `AgentSession` — the orchestrator over flutter_gemma's existing
  function-calling, emitting a `Stream<AgentEvent>` (skill loads, tool calls,
  inline results, streamed text).
- Cross-platform UI: `AgentChatView`, adaptive `SkillManagerView` /
  `McpManagerView`, `SecretEditorDialog`, `SkillTesterView`, and the add-skill
  disclaimer.
- **Bundled starter skills** (ported verbatim from Gallery, Apache-2.0) — see
  below.

## Bundled starter skills

Seven starter skills ship as package assets and cover all four mechanisms:

| Skill | Type | What it does |
|---|---|---|
| `calculate-hash` | JS | Hash a piece of text |
| `qr-code` | JS (image) | Generate a QR code |
| `query-wikipedia` | JS (data) | Summarize a Wikipedia topic |
| `interactive-map` | JS (webview) | Show a location on an embedded map |
| `send-email` | intent | Open the OS mail composer |
| `create-calendar-event` | intent | Open the calendar event editor |
| `kitchen-adventure` | text-only | A text-adventure dungeon-master persona |

Load them with `AssetSkillSource` and wire the JS executor to their bundled HTML:

```dart
final source = AssetSkillSource();
final skills = await source.load();             // parses the bundled SKILL.md
final registry = SkillRegistry()..addAll(skills, selected: true);

final js = JsSkillExecutor(sourceFor: source.jsSkillSourceFor);
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';

// 1. Register the inference engine at app start (skill executors are passed to
//    the AgentSession below, not to initialize).
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
);

// 2. Install + load a function-calling model (Gemma 4 E2B/E4B recommended).
await FlutterGemma
    .installModel(modelType: ModelType.gemma4, fileType: ModelFileType.litertlm)
    .fromNetwork(gemma4E2BUrl)
    .install();
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);

// 3. Load the bundled skills and build the agent session.
final source = AssetSkillSource();
final registry = SkillRegistry()..addAll(await source.load(), selected: true);

final session = await AgentSession.fromModel(
  model,
  registry: registry,
  executors: [
    TextSkillExecutor(),
    JsSkillExecutor(sourceFor: source.jsSkillSourceFor),
    NativeIntentExecutor(),
    // McpSkillExecutor(...) to also call remote MCP tools.
  ],
);

// 4. Mount the chat view.
//   AgentChatView(session: session)
// e.g. "Calculate the hash of hello" or "Show Paris on interactive map".
```

See `packages/flutter_gemma/example` (the **Agent Skills** screen) for a
runnable demo.

## SKILL.md format

```yaml
---
name: kebab-case-id
description: One-line summary the model uses to pick the skill.
metadata:
  homepage: https://optional
  require-secret: true
  require-secret-description: how to obtain the key
---
# Title
## Instructions
Call the `run_js` tool with: script name: index.html, data: { field: Type }
```

JS skills additionally ship `scripts/index.html` exposing
`window.ai_edge_gallery_get_result(data, secret)` returning a JSON string
(`{ result | image | webview | error }`). Secrets are injected as the JS
`secret` argument and **never** placed in the model prompt.

## License

This package is part of the flutter_gemma project. Bundled starter skills are
derived from google-ai-edge/gallery (Apache-2.0).
