# flutter_gemma_builtin_ai

Built-in OS AI engine for [flutter_gemma](https://pub.dev/packages/flutter_gemma): uses the
on-device system model instead of a bundled Gemma checkpoint — Gemini Nano via ML Kit GenAI on
Android and Apple Foundation Models on iOS/macOS. Opt-in package; add it only if you want to run
against the OS-provided model rather than shipping your own weights.

Supported platforms/devices depend on OS-level AI availability: Android devices with ML Kit GenAI
(Gemini Nano) support, and Apple devices with Apple Intelligence (iOS/macOS with Foundation
Models). Availability is queried at runtime and is not guaranteed on every device. This package is
currently a skeleton — engine logic, native plugins, and full documentation land in later tasks.
