# flutter_gemma_embeddings example

`flutter_gemma_embeddings` is an opt-in text-embedding backend for
[`flutter_gemma`](https://pub.dev/packages/flutter_gemma). It runs Gecko /
EmbeddingGemma `.tflite` models via the LiteRT C API (dart:ffi on the 5 native
platforms, LiteRT.js on web). Register the backend once at startup, then embed
text and feed the vectors into any RAG vector store.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opt into the LiteRT embedding backend.
  await FlutterGemma.initialize(
    embeddingBackends: [LiteRtEmbeddingBackend()],
  );

  // Install an embedding model (downloads + sets it active).
  await FlutterGemma.installEmbedder(
    modelType: EmbeddingModelType.embeddingGemma,
  ).fromNetwork(
    'https://example.com/embeddinggemma.tflite',
    tokenizer: 'https://example.com/sentencepiece.model',
  ).install();

  // Create the embedding model and embed text.
  final embedder = await FlutterGemma.getActiveEmbeddingModel();
  final vector = await embedder.generateEmbedding('Gemma runs on-device.');
  print('embedding dim: ${vector.length}');

  await embedder.close();
}
```

Pair this with a RAG vector store (`flutter_gemma_rag_qdrant` on native,
`flutter_gemma_rag_sqlite` for web) to build on-device retrieval. A full runnable
app lives in the
[`flutter_gemma` example](https://github.com/DenisovAV/flutter_gemma/tree/main/packages/flutter_gemma/example).
