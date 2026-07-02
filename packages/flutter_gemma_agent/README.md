# flutter_gemma_agent

On-device agentic **skills** for [flutter_gemma](https://pub.dev/packages/flutter_gemma).

This opt-in satellite package turns the inference core into an on-device agent:
the model is given a set of *skills* (`SKILL.md`), decides which to invoke via
flutter_gemma's existing function-calling, runs them, and feeds the results back
— fully offline.

It is reverse-engineered from [google-ai-edge/gallery](https://github.com/google-ai-edge/gallery)
(Apache-2.0) and is **Gallery-compatible**: their `SKILL.md` catalog parses
unmodified, and their JavaScript skills run as-is (the
`window.ai_edge_gallery_get_result` contract is preserved).

## Platform support

| Skill type | Android | iOS | macOS | Windows | Web | Linux |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| **text-only** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **MCP** (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **native-intent** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **JS** (webview) | ✅ | ✅ | ✅ | ✅¹ | ✅ | ❌² |

¹ Windows JS skills need the [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
(pre-installed on Windows 11; on Windows 10 ship the bootstrapper). See
[Setup](#setup).
² Linux has no embeddable webview, so JS skills return an `ErrorResult`
(`isAvailable` is false). text / native-intent / MCP skills work on Linux.

JS skills run in a headless, sandboxed webview. To grant a secure context (so
skills using `crypto.subtle` and other secure-context Web APIs work), the
package serves each skill's assets over a loopback HTTP server
(`http://127.0.0.1`, a W3C "potentially trustworthy" origin) — one mechanism that
works identically across all native engines (WebView2 / WKWebView / Android
WebView), verified on hardware. On web the skill runs in a sandboxed `<iframe>`.

> **Web is experimental.** The table shows where each skill *type* runs once
> invoked. The agent loop needs the model to emit tool calls, and today's
> browser LLM runtimes don't do this reliably — the LiteRT-LM web runtime
> (`@litert-lm/core`) doesn't consistently emit tool-call tokens, and the
> MediaPipe web runtime returns plain text with no tool-call parsing. So on web
> the model often replies in prose instead of invoking a skill. The agent is
> verified end-to-end on **Android, iOS, macOS, and Windows** — use those for
> real runs; treat web as a preview.

## What's in the box

- `Skill` + `SkillType` (`textOnly` / `js` / `intent` / `mcp`) and the
  `parseSkillMd` parser (YAML frontmatter + markdown body).
- `SkillRegistry` — holds available/selected skills and builds the cheap
  name+description discovery string for the system prompt (two-stage discovery).
- `SkillExecutor` probe-chain (mirrors flutter_gemma's engine registry) + sealed
  `SkillResult` (`TextResult` / `ImageResult` / `WidgetResult` / `WebviewResult`
  / `ErrorResult`).
- Concrete executors: `TextSkillExecutor` (0 deps), `JsSkillExecutor`
  (sandboxed headless webview — `flutter_inappwebview` on native, a `package:web`
  iframe on web), `NativeIntentExecutor` (whitelisted OS intents behind user/OS
  confirm), `McpSkillExecutor` (MCP tools over Streamable HTTP).
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

// 1. Register the inference engine at app start. (Skill executors can also be
//    registered here via `skillExecutors:` — see "Registering executors" below;
//    this example passes them to the AgentSession instead.)
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

## Registering executors

Two equivalent ways to wire executors:

```dart
// A) Pass them per session (shown in the Quick start above):
AgentSession.fromModel(model, registry: registry, executors: [...]);

// B) Register them globally once, then omit `executors:` — fromModel reads the
//    core registry (mirrors how inference engines are registered):
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  skillExecutors: [TextSkillExecutor(), JsSkillExecutor(sourceFor: ...), NativeIntentExecutor()],
);
final session = await AgentSession.fromModel(model, registry: registry);
```

## Setup

Most skills need no platform setup. For the platform-specific bits:

- **Windows** — JS skills require the
  [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
  (pre-installed on Windows 11; bundle the bootstrapper for Windows 10).
- **iOS** — the `create-calendar-event` intent opens the calendar editor via
  `add_2_calendar`, which needs a usage description in `ios/Runner/Info.plist`:
  ```xml
  <key>NSCalendarsUsageDescription</key>
  <string>Create calendar events from the agent.</string>
  ```
  Local notifications (`schedule_notification`) prompt for permission at runtime.
- **Android** — `flutter_local_notifications` requires core-library desugaring in
  `android/app/build.gradle(.kts)`:
  ```kotlin
  android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
  dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
  ```

## Third-party attribution

The bundled starter skills (`calculate-hash`, `qr-code`, `query-wikipedia`,
`interactive-map`, `send-email`, `create-calendar-event`, `kitchen-adventure`)
and the `SKILL.md` format are derived from
[google-ai-edge/gallery](https://github.com/google-ai-edge/gallery), licensed
under the [Apache License 2.0](https://github.com/google-ai-edge/gallery/blob/main/LICENSE).

## License

MIT — see [LICENSE](LICENSE). Bundled starter skills are Apache-2.0 (see above).
