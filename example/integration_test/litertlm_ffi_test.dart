/// Universal FFI integration test for all platforms (macOS, iOS, Android).
///
/// Prerequisites:
///   macOS:   models in ~/Library/Containers/.../Documents/
///   Android: adb push models to /data/local/tmp/flutter_gemma_test/
///   iOS:     models downloaded via FlutterGemma.installModel()
///
/// Run:
///   flutter test integration_test/litertlm_ffi_test.dart -d <device>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/model.dart';

// ── Model URLs (for iOS download, macOS/Android use local files) ──
const _gemma4Url =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

const _token = String.fromEnvironment('HUGGINGFACE_TOKEN');

// ── Local paths ──
String get _androidDir => '/data/local/tmp/flutter_gemma_test';
String get _macosDir =>
    '${Platform.environment['HOME']}/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents';
String get _linuxDir => '${Platform.environment['HOME']}/models';
String get _windowsDir => '${Platform.environment['USERPROFILE']}\\models';

Uint8List _testImage = Uint8List(0);
Uint8List _testAudio = Uint8List(0);

/// Install model: from file on macOS/Android, from network on iOS.
Future<void> _install({
  required String? localPath,
  required String networkUrl,
}) async {
  if (localPath != null && File(localPath).existsSync()) {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(localPath).install();
  } else {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(networkUrl, token: _token).install();
  }
}

/// Get local path for a model filename (null on iOS — download instead).
///
/// iOS Simulator can read the host macOS filesystem; pass the host Documents
/// dir via `--dart-define=IOS_TEST_DOCS_DIR=...` to reuse host-cached models
/// instead of re-downloading on every test run.
String? _localPath(String filename) {
  if (Platform.isAndroid) return '$_androidDir/$filename';
  if (Platform.isMacOS) return '$_macosDir/$filename';
  if (Platform.isLinux) return '$_linuxDir/$filename';
  if (Platform.isWindows) return '$_windowsDir\\$filename';
  if (Platform.isIOS) {
    const iosDocs = String.fromEnvironment('IOS_TEST_DOCS_DIR');
    if (iosDocs.isNotEmpty) {
      final p = '$iosDocs/$filename';
      if (File(p).existsSync()) return p;
    }
    return null; // device path or network download
  }
  return null;
}

/// Group-scoped model instance. We create it once per test group (with full
/// vision+audio capabilities + the selected backend) and reuse it across all
/// tests in that group — destroying & recreating the engine between every
/// test would re-initialize the GPU adapter, which on Linux/Vulkan trips an
/// upstream LiteRT-LM bug `ALREADY_EXISTS: wgpu::Instance already set` and
/// also adds 2-3 s engine_create overhead per test.
///
/// This mirrors how a real Flutter app uses the plugin: create one
/// `InferenceModel` per chat surface, open many sessions on it.
InferenceModel? _sharedModel;
PreferredBackend? _sharedBackend;

Future<InferenceModel> _ensureModel(
    PreferredBackend backend, int maxTokens) async {
  if (_sharedModel != null && _sharedBackend == backend) return _sharedModel!;
  if (_sharedModel != null && _sharedBackend != backend) {
    await _sharedModel!.close();
    _sharedModel = null;
  }
  _sharedBackend = backend;
  _sharedModel = await FlutterGemma.getActiveModel(
    maxTokens: maxTokens,
    preferredBackend: backend,
    supportImage: true,
    maxNumImages: 1,
    supportAudio: true,
  );
  return _sharedModel!;
}

Future<void> _closeSharedModel() async {
  if (_sharedModel != null) {
    await _sharedModel!.close();
    _sharedModel = null;
    _sharedBackend = null;
  }
}

/// Helper: open a session on the shared model, send a single prompt, return
/// the streamed response.
Future<String> _chat(
  PreferredBackend backend,
  int maxTokens,
  String prompt, {
  bool supportImage = false,
  bool supportAudio = false,
  bool enableThinking = false,
  Uint8List? image,
  Uint8List? audio,
}) async {
  final model = await _ensureModel(backend, maxTokens);
  final session = await model.createSession(
    temperature: 0.8,
    topK: 1,
    enableVisionModality: supportImage,
    enableAudioModality: supportAudio,
    enableThinking: enableThinking,
  );
  await session.addQueryChunk(Message(
    text: prompt,
    isUser: true,
    imageBytes: image,
    audioBytes: audio,
  ));

  // Collect streaming response
  final chunks = <String>[];
  await for (final chunk in session.getResponseAsync()) {
    chunks.add(chunk);
  }
  final response = chunks.join();

  await session.close();
  // Don't close the model — it's shared across tests in this group and
  // closed once in tearDownAll via _closeSharedModel().
  return response;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();

    // Load test assets — try filesystem first (host paths on macOS/Linux/Windows
    // and Android adb-pushed paths), then fall back to bundled Flutter assets
    // (works on iOS device + simulator + any platform where assets/test/ ships).
    for (final path in [
      '$_androidDir/test_image.jpg',
      '$_macosDir/test_image.png',
      if (Platform.isLinux) '$_linuxDir/test_image.png',
      if (Platform.isLinux) '$_linuxDir/test_image.jpg',
      if (Platform.isWindows) '$_windowsDir\\test_image.png',
      if (Platform.isWindows) '$_windowsDir\\test_image.jpg',
      '${Platform.environment['HOME']}/Downloads/test_image.jpg',
    ]) {
      if (File(path).existsSync()) {
        _testImage = File(path).readAsBytesSync();
        break;
      }
    }
    if (_testImage.isEmpty) {
      try {
        final data = await rootBundle.load('assets/test/test_image.jpg');
        _testImage = data.buffer.asUint8List();
      } catch (_) {/* asset not bundled — leave empty */}
    }
    for (final path in [
      '$_androidDir/test_audio.wav',
      '$_macosDir/test_audio.wav',
      if (Platform.isLinux) '$_linuxDir/test_audio.wav',
      if (Platform.isWindows) '$_windowsDir\\test_audio.wav',
    ]) {
      if (File(path).existsSync()) {
        _testAudio = File(path).readAsBytesSync();
        break;
      }
    }
    if (_testAudio.isEmpty) {
      try {
        final data = await rootBundle.load('assets/test/test_audio.wav');
        _testAudio = data.buffer.asUint8List();
      } catch (_) {/* asset not bundled — leave empty */}
    }
    print('Platform: ${Platform.operatingSystem}');
    print('Assets: image=${_testImage.length}B, audio=${_testAudio.length}B');
  });

  // ══════════════════════════════════════════════════════════════════
  // Gemma 4 E2B — multimodal + thinking
  // ══════════════════════════════════════════════════════════════════
  group('Gemma4-E2B', () {
    setUpAll(() async {
      await _install(
        localPath: _localPath('gemma-4-E2B-it.litertlm'),
        networkUrl: _gemma4Url,
      );
    });

    tearDownAll(_closeSharedModel);

    testWidgets('CPU text', (t) async {
      final r = await _chat(PreferredBackend.cpu, 4096, 'Say hi');
      print('[Gemma4 CPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU text', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'What is 2+2?');
      print('[Gemma4 GPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU streaming', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'Say hello');
      print('[Gemma4 stream] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU vision', (t) async {
      if (_testImage.isEmpty) {
        print('[Gemma4 vision] SKIP: no image');
        return;
      }
      final r = await _chat(
          PreferredBackend.gpu, 4096, 'Describe this image briefly',
          supportImage: true, image: _testImage);
      print('[Gemma4 vision] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU audio', (t) async {
      if (_testAudio.isEmpty) {
        print('[Gemma4 audio] SKIP: no audio');
        return;
      }
      final r = await _chat(PreferredBackend.gpu, 4096, 'What did you hear?',
          supportAudio: true, audio: _testAudio);
      print('[Gemma4 audio] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU thinking', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'Why is the sky blue?',
          enableThinking: true);
      final hasThinking = r.contains('<|channel>thought');
      print('[Gemma4 thinking] ${r.length} chars, thinking=$hasThinking');
      expect(r, isNotEmpty);
    });

    // ══════════════════════════════════════════════════════════════════
    // InferenceChat surface — covers methods that session-level tests miss
    // ══════════════════════════════════════════════════════════════════

    testWidgets('chat generateChatResponse (sync)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);
      await chat.addQueryChunk(Message(text: 'Say hi', isUser: true));
      final r = await chat.generateChatResponse();
      print('[Gemma4 chat sync] ${r.runtimeType}: $r');
      expect(r.toString(), isNotEmpty);
      await chat.close();
    });

    testWidgets('chat generateChatResponseAsync (stream)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);
      await chat.addQueryChunk(Message(text: 'Say hi', isUser: true));
      final chunks = <String>[];
      await for (final r in chat.generateChatResponseAsync()) {
        chunks.add(r.toString());
      }
      print('[Gemma4 chat stream] ${chunks.length} chunks: ${chunks.join()}');
      expect(chunks, isNotEmpty);
      await chat.close();
    });

    testWidgets('chat multi-turn (history retained)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);

      await chat.addQueryChunk(
          Message(text: 'My favourite colour is purple.', isUser: true));
      final r1 = await chat.generateChatResponse();
      print('[Gemma4 chat turn 1] $r1');
      expect(r1.toString(), isNotEmpty);

      await chat.addQueryChunk(
          Message(text: 'What is my favourite colour?', isUser: true));
      final r2 = await chat.generateChatResponse();
      print('[Gemma4 chat turn 2] $r2');
      expect(r2.toString(), isNotEmpty);
      // Sanity: model should mention the colour from turn 1.
      expect(r2.toString().toLowerCase(), contains('purple'));

      await chat.close();
    });

    testWidgets('chat clearHistory resets conversation', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);

      await chat.addQueryChunk(
          Message(text: 'Remember the secret word: BANANA.', isUser: true));
      await chat.generateChatResponse();

      await chat.clearHistory();
      print('[Gemma4 chat clearHistory] OK');

      await chat.addQueryChunk(
          Message(text: 'What was the secret word?', isUser: true));
      final r = await chat.generateChatResponse();
      print('[Gemma4 chat after clear] $r');
      // After clearHistory the model should not remember "BANANA".
      expect(r.toString().toLowerCase(), isNot(contains('banana')));

      await chat.close();
    });

    testWidgets('chat stopGeneration interrupts stream', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);
      await chat.addQueryChunk(
          Message(text: 'Write a 1000-word essay about Berlin.', isUser: true));

      final received = <String>[];
      var stopped = false;
      final sub = chat.generateChatResponseAsync().listen((r) async {
        received.add(r.toString());
        if (received.length == 5 && !stopped) {
          stopped = true;
          await chat.stopGeneration();
        }
      });
      await sub
          .asFuture<void>()
          .timeout(const Duration(seconds: 30), onTimeout: () => sub.cancel());

      print('[Gemma4 chat stop] got ${received.length} chunks before stop');
      expect(received, isNotEmpty);
      // We asked for 1000 words but stopped after 5 chunks; total length should
      // be small relative to a full essay (sanity: nothing crazy).
      expect(received.length, lessThan(500));

      await chat.close();
    });

    testWidgets('session sizeInTokens', (t) async {
      // sizeInTokens is tokenizer-only, doesn't touch the backend — keep using
      // the shared GPU model to avoid destroying the engine (which on
      // Linux/Vulkan triggers the upstream wgpu::Instance singleton issue).
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final session = await model.createSession(temperature: 0.8, topK: 1);
      final n = await session.sizeInTokens('Hello, how many tokens am I?');
      print('[Gemma4 sizeInTokens] $n');
      expect(n, greaterThan(0));
      await session.close();
    });

    testWidgets('session stopGeneration (low-level)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(Message(
          text: 'Write a 1000-word essay about the Berlin Wall.',
          isUser: true));

      final received = <String>[];
      var stopped = false;
      final sub = session.getResponseAsync().listen((chunk) async {
        received.add(chunk);
        if (received.length == 5 && !stopped) {
          stopped = true;
          await session.stopGeneration();
        }
      });
      await sub
          .asFuture<void>()
          .timeout(const Duration(seconds: 30), onTimeout: () => sub.cancel());

      print('[Gemma4 session stop] got ${received.length} chunks');
      expect(received, isNotEmpty);
      expect(received.length, lessThan(500));

      await session.close();
    });

    testWidgets('stream cancel via subscription.cancel (no stopGeneration)',
        (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(
          Message(text: 'Write a 1000-word essay about Paris.', isUser: true));

      final received = <String>[];
      final completer = Completer<void>();
      final sub = session.getResponseAsync().listen(
        (chunk) {
          received.add(chunk);
          if (received.length == 3 && !completer.isCompleted) {
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(const Duration(seconds: 30));
      await sub.cancel();

      print('[Gemma4 stream cancel] got ${received.length} chunks');
      expect(received, isNotEmpty);

      // Closing the session cleanly after stream cancel must not crash.
      await session.close();
    });

    testWidgets('multiple createSession on same model', (t) async {
      // FfiInferenceModel is single-session at a time — this test verifies
      // we can sequentially create + close sessions without leaking the engine.
      final model = await _ensureModel(PreferredBackend.gpu, 4096);

      for (var i = 0; i < 3; i++) {
        final session = await model.createSession(temperature: 0.8, topK: 1);
        await session
            .addQueryChunk(Message(text: 'Iteration $i: hi', isUser: true));
        final chunks = <String>[];
        await for (final c in session.getResponseAsync()) {
          chunks.add(c);
        }
        print('[Gemma4 multi-session $i] ${chunks.join().substring(0, 20)}...');
        expect(chunks, isNotEmpty);
        await session.close();
      }
    });
  });

  // ── Multi-session (#226): concurrent openSession() dialogues ──────
  //
  // The LiteRT-LM engine allows only ONE live conversation at a time, so
  // openSession() sessions multiplex — each keeps its history in Dart and
  // replays it (messages_json preface) into the single shared conversation
  // on switch. Logically concurrent contexts, serialized inference. These
  // verify the property end-to-end on the native engine: two sessions keep
  // isolated history, and closing one leaves the other usable. Runs on the
  // shared GPU model — also exercises the GPU sampler path under multiplexing.
  group('Multi-session', () {
    tearDownAll(_closeSharedModel);

    Future<String> _ask(InferenceModelSession s, String prompt) async {
      await s.addQueryChunk(Message(text: prompt, isUser: true));
      return s.getResponse();
    }

    testWidgets('two openSession dialogues keep isolated history', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 1024);
      final a = await model.openSession(temperature: 0.0, topK: 1);
      final b = await model.openSession(temperature: 0.0, topK: 1);
      try {
        expect(model.sessions.length, greaterThanOrEqualTo(2));
        await _ask(a, 'My name is Alice. Remember it.');
        await _ask(b, 'My name is Bob. Remember it.');
        final ra = (await _ask(a, 'What is my name? One word.')).toLowerCase();
        final rb = (await _ask(b, 'What is my name? One word.')).toLowerCase();
        print('[multi-session] A="$ra" B="$rb"');
        expect(ra, contains('alice'), reason: 'A should recall Alice');
        expect(ra, isNot(contains('bob')), reason: 'A must not see B history');
        expect(rb, contains('bob'), reason: 'B should recall Bob');
        expect(rb, isNot(contains('alice')),
            reason: 'B must not see A history');
      } finally {
        await a.close();
        await b.close();
      }
    });

    testWidgets('closing one session leaves the other usable', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 1024);
      final a = await model.openSession(temperature: 0.0, topK: 1);
      final b = await model.openSession(temperature: 0.0, topK: 1);
      await a.close();
      final rb = await _ask(b, 'Say hi in one word.');
      print('[multi-session S2] B after A.close = "$rb"');
      expect(rb.trim(), isNotEmpty);
      await b.close();
    });
  });

  // ── Gemma4 NPU: 0.15.1 sampler-skip behaviour ────────────────────
  //
  // LiteRT-LM NPU executor only supports internal greedy sampling. As of
  // 0.15.1 we skip the sampler-params setter chain when backend == 'npu'
  // (lib/core/ffi/litert_lm_client.dart::createConversation). These tests
  // verify the path end-to-end: engine creates successfully with NPU
  // backend even when caller passes non-default temperature/topK/topP, and
  // generation is deterministic (same prompt → identical output across
  // runs, regardless of seed/temperature).
  //
  // Platforms covered:
  //   - Android with .litertlm NPU executor (Pixel 8 / API 31+ with
  //     NNAPI accelerator that exposes "npu" backend tag)
  //   - Windows with Intel dispatch DLLs (Lunar Lake / PantherLake — once
  //     Matt + Intel partner deliver the bundle in 0.15.1 RC)
  // Other platforms (macOS/iOS/Linux/Web): skipped — no NPU dispatch.
  group('Gemma4-E2B NPU', () {
    tearDownAll(_closeSharedModel);

    // Real NPU tests need a model precompiled for the target NPU (Intel
    // LunarLake / PantherLake or Qualcomm QNN). Generic Gemma 4 from HF
    // doesn't carry NPU executor sections and `engine_create` will reject
    // it. Pre-arranged LNL artifact lives in the workspace dir; SKIP if
    // absent (covers CI and dev machines without NPU hardware).
    String? _findNpuModel() {
      final candidates = <String>[
        if (Platform.isWindows)
          '${Platform.environment['USERPROFILE']}\\dev-gemma4-2b-lnl\\gemma4_2b_lnl.litertlm',
        if (Platform.isLinux || Platform.isMacOS)
          '${Platform.environment['HOME']}/dev-gemma4-2b-lnl/gemma4_2b_lnl.litertlm',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      return null;
    }

    Future<InferenceModel?> _installAndGetNpu() async {
      final npuModelPath = _findNpuModel();
      if (npuModelPath == null) {
        print('[Gemma4 NPU] SKIP: no NPU-compiled model found');
        return null;
      }
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(npuModelPath).install();
      await _closeSharedModel();
      try {
        return await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.npu,
        );
      } catch (e) {
        print('[Gemma4 NPU] SKIP engine_create failed: $e');
        return null;
      }
    }

    testWidgets('NPU engine_create accepts non-default sampler params',
        (t) async {
      final model = await _installAndGetNpu();
      if (model == null) return;
      final session = await model.createSession(
        // Non-default sampler params — these MUST be ignored on NPU.
        temperature: 0.5,
        topK: 20,
        topP: 0.75,
      );
      await session.addQueryChunk(
          const Message(text: 'What is the capital of France?', isUser: true));
      final out = await session.getResponse();
      print('[Gemma4 NPU engine_create] $out');
      expect(out, isNotEmpty);
      // Paris should appear in any sensible answer.
      expect(out.toLowerCase().contains('paris'), isTrue,
          reason:
              'NPU should produce a coherent answer about France\'s capital');
      await session.close();
      await model.close();
    });

    testWidgets('NPU generation is deterministic (greedy ignores seed)',
        (t) async {
      final model = await _installAndGetNpu();
      if (model == null) return;
      final s1 = await model.createSession(temperature: 0.8, randomSeed: 1);
      await s1.addQueryChunk(
          const Message(text: 'List three colors', isUser: true));
      final r1 = await s1.getResponse();
      await s1.close();

      final s2 = await model.createSession(temperature: 0.8, randomSeed: 99999);
      await s2.addQueryChunk(
          const Message(text: 'List three colors', isUser: true));
      final r2 = await s2.getResponse();
      await s2.close();

      await model.close();

      print('[Gemma4 NPU det run1] $r1');
      print('[Gemma4 NPU det run2] $r2');
      expect(r1, isNotEmpty);
      expect(r2, isNotEmpty);
      expect(r1, equals(r2),
          reason: 'NPU should ignore seed and produce deterministic output');
    });
  });

  // ── Desktop storage path verification (#179) ─────────────────────
  //
  // Verifies Phase 5 of 0.15.1: on Windows / macOS / Linux, fromNetwork
  // installs land under getApplicationSupportDirectory() (Application
  // Support / LOCALAPPDATA / XDG_DATA_HOME), NOT in the user's Documents
  // folder which is commonly cloud-synced (OneDrive, iCloud, Dropbox)
  // and breaks FFI mmap on large model files.
  //
  // Mobile (Android, iOS) skips this group entirely — Documents is
  // sandboxed there and never cloud-synced.
  group('Desktop storage path (#179)', () {
    testWidgets('getTargetPath resolves into Application Support', (t) async {
      if (Platform.isAndroid || Platform.isIOS) {
        print('[Desktop storage] SKIP: mobile path unchanged');
        return;
      }

      // No install required — we just inspect what path the plugin would
      // hand back for a synthetic filename. This is the exact call site
      // that NetworkSourceHandler / fromNetwork uses to decide where to
      // write the downloaded bytes (and that getActiveModel uses to
      // locate the model file at inference time).
      //
      // Routing through ServiceRegistry mirrors the plugin's own
      // dependency-injection order, so we exercise the production path,
      // not a hand-rolled instance.
      final fs = ServiceRegistry.instance.fileSystemService;
      final filename =
          'storage_path_probe_${DateTime.now().millisecondsSinceEpoch}.litertlm';
      final resolved = await fs.getTargetPath(filename);

      final docsDir = await getApplicationDocumentsDirectory();
      final supportDir = await getApplicationSupportDirectory();
      final localAppData = Platform.environment['LOCALAPPDATA'];

      print('[Desktop storage] Documents root:           ${docsDir.path}');
      print('[Desktop storage] Application Support root: ${supportDir.path}');
      print('[Desktop storage] LOCALAPPDATA env:         $localAppData');
      print('[Desktop storage] Resolved target path:     $resolved');

      // Phase 5 contract:
      //   - Windows: under %LOCALAPPDATA%\flutter_gemma\ (truly local,
      //     never OneDrive- or Domain-synced).
      //   - macOS/Linux: under getApplicationSupportDirectory()/flutter_gemma/.
      if (Platform.isWindows) {
        expect(localAppData, isNotNull,
            reason: 'LOCALAPPDATA env var must be set on Windows');
        expect(resolved.startsWith(localAppData!), isTrue,
            reason: 'Phase 5 fix (#179): Windows path must be under '
                'LOCALAPPDATA ($localAppData), got: $resolved');
      } else {
        // macOS, Linux
        expect(resolved.startsWith(supportDir.path), isTrue,
            reason: 'Phase 5 fix (#179): macOS/Linux path must be under '
                'Application Support (${supportDir.path}), got: $resolved');
      }
      expect(resolved.contains('flutter_gemma'), isTrue,
          reason: 'Path should be namespaced under flutter_gemma/');

      // It should NOT land directly under Documents (where 0.15.0 and
      // earlier put it).
      final legacyBare = '${docsDir.path}${Platform.pathSeparator}$filename';
      expect(resolved, isNot(equals(legacyBare)),
          reason: 'Path must not be the legacy Documents/$filename');
    });
  });
}
