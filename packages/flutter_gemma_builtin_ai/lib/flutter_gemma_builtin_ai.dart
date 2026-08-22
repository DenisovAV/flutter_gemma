/// Built-in OS AI engine for flutter_gemma (Gemini Nano / Apple Foundation
/// Models / Chrome Prompt API).
library;

// Shared, arm-neutral: pure Dart, no platform imports either side.
export 'src/availability_types.dart'; // BuiltInAiAvailability, BuiltInAiUnavailableException
export 'src/builtin_ai_models.dart'; // BuiltInAiModels specs

// Swapped arm — native (dart:ffi true on Android/iOS/macOS) vs web
// (dart2js/dart2wasm, dart:ffi false). Mirrors flutter_gemma_litertlm's
// barrel split exactly.
export 'src/web/builtin_ai_engine_web.dart'
    if (dart.library.ffi) 'src/builtin_ai_engine.dart'; // BuiltInAiEngine

export 'src/web/availability_web.dart'
    if (dart.library.ffi) 'src/availability.dart'
    show
        BuiltInAi; // facade only — service/channel/mapAvailability/interop stay internal
