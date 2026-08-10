// Full on-device RAG end-to-end: embed → store in Qdrant Edge → retrieve →
// generate an answer with the retrieved context. Exercises the whole stack on a
// real device runtime (iOS simulator / Android emulator):
//
//   embeddings  : flutter_gemma_embeddings  (LiteRT, Gecko-110m, 768-D, CPU)
//   vector store: flutter_gemma_rag_qdrant  → the official qdrant_edge UniFFI SDK
//   generation  : flutter_gemma_mediapipe   (functiongemma-270M-it .task, CPU)
//
// Models (both non-gated) are taken from a local adb-pushed path if present
// (fast on the emulator) else downloaded at runtime (works on the iOS sim):
//   emb: Gecko_64_quant.tflite            (~107 MB) + committed gecko tokenizer
//   gen: functiongemma-270M-it.task       (~271 MB)
//
// Run: flutter test integration_test/rag_e2e_test.dart -d <device-id>

import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _embUrl =
    'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_64_quant.tflite';
// Gecko's own SentencePiece tokenizer (desktop path — see note below).
const _embTokenizerUrl =
    'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model';
// Generation model: MediaPipe `.task` on mobile, LiteRT-LM `.litertlm` on desktop
// (MediaPipe LLM inference is mobile-only; desktop runs the litertlm backend).
const _genTaskUrl =
    'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task';
const _genLitertlmUrl =
    'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm';
// Optional adb-pushed fast path (Android): `adb push <file> /data/local/tmp/qe_rag/`.
const _pushDir = '/data/local/tmp/qe_rag';
const _embPath = '$_pushDir/Gecko_64_quant.tflite';

bool get _desktop => Platform.isMacOS || Platform.isLinux || Platform.isWindows;
ModelFileType get _genType =>
    _desktop ? ModelFileType.litertlm : ModelFileType.task;
String get _genUrl => _desktop ? _genLitertlmUrl : _genTaskUrl;
String get _genPath =>
    '$_pushDir/functiongemma-270M-it.${_desktop ? 'litertlm' : 'task'}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'RAG e2e: embed → Qdrant Edge store → retrieve → Gemma generate',
    (tester) async {
      await tester.runAsync(() async {
        // 1. Register the LiteRT-LM + MediaPipe inference engines, the LiteRT
        //    embedding backend, and the qdrant_edge-backed vector store.
        await FlutterGemma.initialize(
          inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
          embeddingBackends: const [LiteRtEmbeddingBackend()],
          vectorStore: QdrantVectorStore(),
        );

        // 2. Install the embedding model (from a pushed file if present, else
        //    download). Tokenizer ships as a committed asset.
        var eb = FlutterGemma.installEmbedder();
        eb = File(_embPath).existsSync()
            ? eb.modelFromFile(_embPath)
            : eb.modelFromNetwork(_embUrl);
        // large_file_handler cannot copy a Flutter asset on macOS (throws a 404),
        // so on desktop fetch the tokenizer over the network; mobile uses the
        // committed asset (works on iOS/Android).
        eb = _desktop
            ? eb.tokenizerFromNetwork(_embTokenizerUrl)
            : eb.tokenizerFromAsset('assets/models/gecko_tokenizer.json');
        await eb.install();

        final embedder = await FlutterGemma.getActiveEmbedder();

        // 3. Open a fresh shard and index a few distinct documents. rag.
        //    addDocument auto-embeds with TaskType.retrievalDocument.
        final shardDir =
            '${(await getApplicationSupportDirectory()).path}/qe_rag_e2e_'
            '${DateTime.now().microsecondsSinceEpoch}';
        addTearDown(() {
          final d = Directory(shardDir);
          if (d.existsSync()) d.deleteSync(recursive: true);
        });
        await FlutterGemma.rag.initialize(shardDir);
        await FlutterGemma.rag.addDocument(
          id: 'qdrant',
          content:
              'Qdrant Edge is an on-device vector database that runs in-process '
              'with no server and no network, using an HNSW index for fast '
              'nearest-neighbour search.',
        );
        await FlutterGemma.rag.addDocument(
          id: 'eiffel',
          content:
              'The Eiffel Tower is a wrought-iron lattice tower on the Champ de '
              'Mars in Paris, France, completed in 1889.',
        );
        await FlutterGemma.rag.addDocument(
          id: 'photosynthesis',
          content:
              'Photosynthesis is the process by which green plants convert '
              'sunlight, water and carbon dioxide into chemical energy.',
        );

        // The embedding worker loads its model lazily on the first embed, which
        // the addDocument calls above have now forced; only then is the
        // auto-detected output dimension populated. (Checking it right after
        // getActiveEmbedder races the worker isolate's load on slower hosts.)
        expect(await embedder.getDimension(), 768,
            reason: 'Gecko produces 768-dim embeddings');

        // 4. Retrieve — the query auto-embeds with TaskType.retrievalQuery.
        const question = 'What is Qdrant Edge and how does it search?';
        final hits = await FlutterGemma.rag.searchSimilar(query: question, topK: 3);
        expect(hits, isNotEmpty, reason: 'retrieval returned nothing');
        expect(hits.first.id, 'qdrant',
            reason: 'the Qdrant doc must rank first for a Qdrant query; '
                'got ${hits.map((h) => h.id).toList()}');

        // 5. Install the generation model (pushed file or download) and open a
        //    CPU session (simulator/emulator have no usable GPU delegate).
        var ib = FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
          fileType: _genType,
        );
        ib = File(_genPath).existsSync() ? ib.fromFile(_genPath) : ib.fromNetwork(_genUrl);
        await ib.install();

        final model = await FlutterGemma.getActiveModel(
          maxTokens: 1024,
          preferredBackend: PreferredBackend.cpu,
        );
        final session = await model.createSession();

        // 6. Retrieval-augmented generation: stuff the retrieved context into
        //    the prompt (no orchestrator does this step for us) and generate.
        final context = hits.map((h) => h.content).join('\n');
        final prompt =
            'Use only the context to answer.\n\nContext:\n$context\n\n'
            'Question: $question\nAnswer:';
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        final answer = await session.getResponse();

        expect(answer.trim(), isNotEmpty, reason: 'generation produced no text');

        await session.close();
        await model.close();
        await embedder.close();
      });
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
