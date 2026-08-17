# flutter_gemma_onnx

ONNX Runtime GenAI on-device inference engine for
[flutter_gemma](https://pub.dev/packages/flutter_gemma).

**Status: scaffold only.** `OnnxEngine` registers as an `InferenceEngineProvider`
that claims `ModelFileType.onnx` specs, but `createModel` currently throws
`UnimplementedError('inference — pending throughput gate')`. Productionizing
the ORT-GenAI FFI inference arm is gated on a device generation-throughput
go/no-go measurement — see
`docs/superpowers/plans/2026-08-18-onnx-engine-hardened-plan.md` (D2) in the
flutter_gemma monorepo.

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';

await FlutterGemma.initialize(
  inferenceEngines: const [OnnxEngine()],
);
```

Platforms (planned, once the throughput gate passes): Android, iOS, macOS,
Windows, Linux. No web — ORT-GenAI has no WASM build.
