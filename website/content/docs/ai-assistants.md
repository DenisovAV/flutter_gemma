---
title: AI Assistant Skills
description: flutter_gemma ships agent skills for coding assistants — Claude Code, Codex, Cursor, Copilot and others learn the API from skills bundled in the package, installed with one dart run skills@ get.
image: https://fluttergemma.dev/images/og-image.png
---

A coding assistant that has never seen flutter_gemma writes plausible code that
fails. It installs a `.litertlm` model without declaring its file type and lands
on the wrong engine, reads `maxTokens` as the reply length, or leaves out
`isUser: true` and gets an empty reply.

flutter_gemma ships **agent skills** — instruction files in the open
[Agent Skills](https://agentskills.io) format — inside the package itself.
Dart's [`skills` CLI](https://dart.dev/blog/skills-cli-1-0-bundle-and-distribute-ai-agent-skills-for-your-packages)
copies them into your project, where your assistant picks them up.

<Info>
Not to be confused with <a href="/docs/agent">Agent Skills</a> — the
<code>flutter_gemma_agent</code> package, which gives the <em>on-device model</em>
skills to run. The skills on this page teach <em>your coding assistant</em> to
use flutter_gemma.
</Info>

## Install

From your app's root, once `flutter_gemma` 1.8.1 or later is a dependency:

```
dart run skills@ get --all
```

The CLI scans your dependencies, finds the skills they bundle, and installs
them for the assistant it detects in the project:

| Assistant | `--agent` | Installed to |
|-----------|-----------|--------------|
| Claude Code | `claude` | `.claude/skills/` |
| Codex, Antigravity | `codex`, `antigravity` | `.agents/skills/` |
| Cursor | `cursor` | `.cursor/skills/` |
| GitHub Copilot | `copilot` | `.github/skills/` |
| Cline | `cline` | `.cline/skills/` |
| OpenCode | `opencode` | `.opencode/skills/` |
| any other | `generic` | `.agents/skills/` |

Detection looks for the assistant's directory in the project root. When there is
none yet, the CLI stops with *Could not auto-detect agent* — name the assistant:

```
dart run skills@ get --all --agent claude
```

Copilot is never auto-detected, because `.github/` serves many other purposes,
so it always needs `--agent copilot`. `--all` installs everything without
asking; `--skill <name>` installs a single skill. The CLI records what it
installed in `.config/dart_skills/skills_config.json`.

Run the same command after upgrading flutter_gemma: it updates the installed
skills to the ones the new version ships.

## How your assistant uses them

Each skill is a folder with a `SKILL.md`: a description of when it applies, then
rules, working code, and the traps that fail without an error. The assistant
reads only the descriptions up front and loads a skill when a task matches —
"add an offline chat with Gemma" pulls in the inference skill, "search my notes
by meaning" the RAG one. In Claude Code they install as skills the model invokes
on its own; there is no command to remember.

## The skills

| Skill | Covers |
|-------|--------|
| `flutter-gemma-inference` | engines, installing a model from Hugging Face, sessions and chats, streaming, system prompts, images and audio, backends — and the platform setup for Android, iOS, macOS, Windows, Linux and web |
| `flutter-gemma-function-calling` | declaring tools, `FunctionCallResponse`, the built-in tool loop, returning errors as results |
| `flutter-gemma-rag` | embedding models, `flutter_gemma_rag_sqlite` and `flutter_gemma_rag_qdrant`, metadata filters and their schema |
| `flutter-gemma-speech` | Whisper, moonshine and Parakeet STT; Matcha, Qwen3 and Inflect TTS; 16 kHz PCM; `VoiceSession` |
| `flutter-gemma-mediapipe` | `.task` and `.bin` models on Android, iOS and web |
| `flutter-gemma-onnx` | ORT-GenAI generation and ONNX embeddings, native and through Transformers.js |
| `flutter-gemma-builtin-ai` | Gemini Nano and Apple Foundation Models, availability, falling back to a downloaded model |

## What they prevent

The skills spell out the defaults that fail quietly, each with its fix:

- `maxTokens` is the context window, not the reply length — cap a reply with `maxOutputTokens`.
- `Message.isUser` defaults to `false`; a prompt without it gets an empty reply.
- The declared `fileType`, not the file name, picks the engine, and it defaults to `.task`.
- A metadata filter on a field missing from `filterSchema` is ignored, and search returns unfiltered results.
- Speech-to-text takes raw 16 kHz mono PCM. A WAV file or 48 kHz audio is not rejected — it is transcribed wrong.
- The engine packages do not re-export core: import `package:flutter_gemma/flutter_gemma.dart` as well.

## Kept in step with the code

Every code block in the skills is compiled against the real packages before each
release, and a release that changes an API a skill describes gets that skill
re-read and updated. The skills ship inside the package, so upgrading
flutter_gemma and re-running the CLI keeps your assistant current.
