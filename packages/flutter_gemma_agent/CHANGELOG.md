## 0.1.0

* Initial pure-Dart foundation: Skill model + SKILL.md parser (Gallery-compatible).
* Sealed SkillResult (text/image/widget/webview/error) + SkillExecutor probe-chain abstraction.
* SkillRegistry (select/discovery string) + in-memory SecretStore (never in prompt).
* Agent loop over existing function-calling: 4 built-in tools, parallel-call dispatch, maxIterations guard.
* AgentSession facade (ask → AgentEvent stream) with two-stage skill discovery + injected secrets.
* TextSkillExecutor (0 deps): text-only persona skills resolve to a no-op acknowledgement.
* McpSkillExecutor + McpClient: call MCP tools over Streamable HTTP with a per-call permission hook (default-deny).
* NativeIntentExecutor: whitelist of 6 OS intents (email/SMS/calendar/notification/date) with param validation, behind user confirm.
* AgentChatView: chat widget over the AgentEvent stream with a collapsible progress panel + inline image/webview/widget results.
* Adaptive SkillManagerView + McpManagerView (bottom sheet on narrow, side panel on wide).
* SecretEditorDialog, McpToolCallPermissionDialog, SkillTesterView, and the add-skill security disclaimer.
* Bundled 7 starter skills (Gallery, Apache-2.0): JS/intent/text covering all four mechanisms.
* AssetSkillSource: load bundled SKILL.md skills + wire JsSkillExecutor to their bundled HTML.
