---
title: Agent Skills
description: On-device agentic skills for flutter_gemma — give the model a SKILL.md catalog and let it pick and run skills through the tool-calling loop, fully offline.
image: https://fluttergemma.dev/images/og-image.png
---

`flutter_gemma_agent` is an opt-in satellite package that turns the inference
core into an on-device **agent**: you give the model a set of *skills*
(`SKILL.md` files), and it decides which to invoke through flutter_gemma's
existing function-calling, runs them, and feeds the results back — fully offline.

It is reverse-engineered from
[google-ai-edge/gallery](https://github.com/google-ai-edge/gallery) (Apache-2.0)
and is **Gallery-compatible**: their `SKILL.md` catalog parses unmodified, and
their JavaScript skills run as-is.

<Info>
Agent skills build on function calling, so they need a function-calling-capable
model (Gemma 4 E2B/E4B recommended). See <a href="/docs/function-calling">Function
Calling</a> for the model support matrix.
</Info>

## The four skill mechanisms

A skill is a Markdown file (`SKILL.md`) with YAML frontmatter and one of four
execution mechanisms:

| Skill type | What it does | Android | iOS | macOS | Windows | Web | Linux |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| **text-only** | A persona / instruction the model follows directly | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **MCP** | Calls remote MCP tools over Streamable HTTP | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **native-intent** | Opens an OS surface (mail, SMS, calendar, notification) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **JS** | Runs the skill's JavaScript in a sandboxed headless webview | ✅ | ✅ | ✅ | ✅¹ | ✅ | ❌² |

¹ Windows JS skills need the
[WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
(pre-installed on Windows 11). ² Linux has no embeddable webview, so JS skills
return an `ErrorResult`; text / native-intent / MCP skills work on Linux.

JS skills run in a headless, sandboxed webview. To grant a secure context (so
skills using `crypto.subtle` and other secure-context Web APIs work), the package
serves each skill's assets over a loopback HTTP server (`http://127.0.0.1`, a W3C
"potentially trustworthy" origin) — one mechanism that works identically across
WebView2 / WKWebView / Android WebView, verified on hardware. On the web the skill
runs in a sandboxed `<iframe>`.

## Quick start

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';

// 1. Register the inference engine (and, optionally, the skill executors).
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
);

// 2. Install + load a function-calling model (Gemma 4 E2B/E4B recommended).
await FlutterGemma
    .installModel(modelType: ModelType.gemma4, fileType: ModelFileType.litertlm)
    .fromNetwork(gemma4E2BUrl)
    .install();
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);

// 3. Load the bundled starter skills and build the agent session.
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

The package also ships an adaptive UI: `AgentChatView`, `SkillManagerView`,
`McpManagerView`, `SecretEditorDialog`, and `SkillTesterView`.

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

Two equivalent ways to wire executors — pass them per session, or register them
once globally and let `fromModel` read the core registry (mirrors how inference
engines are registered):

```dart
// Global registration (then omit `executors:` on fromModel):
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
- **iOS** — the `create-calendar-event` intent needs a usage description in
  `ios/Runner/Info.plist`:
  ```xml
  <key>NSCalendarsUsageDescription</key>
  <string>Create calendar events from the agent.</string>
  ```
- **Android** — `schedule_notification` requires core-library desugaring in
  `android/app/build.gradle(.kts)`:
  ```kotlin
  android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
  dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }
  ```

<Warning>
Adding a skill grants the model the ability to run that skill's code or open OS
surfaces. Only load skills you trust — `require-secret` skill keys are stored in
memory and passed to the skill, never to the model prompt.
</Warning>

## Third-party attribution

The bundled starter skills and the `SKILL.md` format are derived from
[google-ai-edge/gallery](https://github.com/google-ai-edge/gallery), licensed
under the Apache License 2.0. `flutter_gemma_agent` itself is MIT-licensed.
