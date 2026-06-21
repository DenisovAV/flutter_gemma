# flutter_gemma_onnx_embeddings

On-device text embeddings for [flutter_gemma](https://pub.dev/packages/flutter_gemma):
EmbeddingGemma `.onnx`/`.ort` models via ONNX Runtime + `dart:ffi`. Opt-in
package — add it only if you compute embeddings (e.g. for on-device RAG).
Android, iOS, macOS, Linux, Windows.

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';

await FlutterGemma.initialize(
  embeddingBackends: [OnnxEmbeddingBackend()],
);
```

`OnnxEmbeddingBackend` handles any `EmbeddingModelSpec` whose model source
resolves to an `.onnx` or `.ort` file.

> **Note:** Full inference is not yet implemented (Task A3). This version
> exports the provider identity for registration purposes.
