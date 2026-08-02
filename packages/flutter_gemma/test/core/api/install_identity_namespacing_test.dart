// Install-identity namespacing (2026-08-02): end-to-end builder tests
// proving companion files (LoRA, embedding/STT tokenizers, TTS bundle
// members) install under a per-model-namespaced identity, using the exact
// PathProviderPlatform-fixture pattern already established in
// test/core/api/stt_install_plumbing_test.dart.
//
// Run: flutter test test/core/api/install_identity_namespacing_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart'
    show MobileModelManager;

// FileSourceHandler enforces a minimum size per extension (1MB for model
// files, 1KB for small/config extensions like .json) to catch truncated
// downloads — fixtures below must clear both thresholds.
final _fakeModelBytes = Uint8List(1024 * 1024 + 16);
final _fakeCompanionBytes = Uint8List(2048);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fakeDocuments;
  late Directory fakeAppSupport;
  late Directory sourceDir;

  setUp(() async {
    fakeDocuments = await Directory.systemTemp.createTemp(
      'flutter_gemma_docs_',
    );
    fakeAppSupport = await Directory.systemTemp.createTemp(
      'flutter_gemma_appsupport_',
    );
    sourceDir = await Directory.systemTemp.createTemp('flutter_gemma_src_');
    PathProviderPlatform.instance = _FixedPathProviderPlatform(
      documentsPath: fakeDocuments.path,
      appSupportPath: fakeAppSupport.path,
    );
    SharedPreferences.setMockInitialValues({});
    ServiceRegistry.reset();
  });

  tearDown(() async {
    ServiceRegistry.reset();
    for (final dir in [fakeDocuments, fakeAppSupport, sourceDir]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  });

  group('Task 4: builder namespacing wiring', () {
    test(
      'InferenceInstallationBuilder namespaces the LoRA file by the model',
      () async {
        await ServiceRegistry.initialize();

        final modelFile = File(path.join(sourceDir.path, 'model.bin'));
        await modelFile.writeAsBytes(_fakeModelBytes);
        final loraFile = File(path.join(sourceDir.path, 'lora.bin'));
        // .bin is NOT in FileNameUtils.isSmallFile's list (only .json/.model
        // are) — use the >=1MB fixture, not the 2KB companion one, so this
        // stays correct even if a size-floor check is ever added to this
        // path later.
        await loraFile.writeAsBytes(_fakeModelBytes);

        await FlutterGemma.installModel(
          modelType: ModelType.general,
        ).fromFile(modelFile.path).withLoraFromFile(loraFile.path).install();

        final repository = ServiceRegistry.instance.modelRepository;
        expect(await repository.isInstalled('model.bin'), isTrue);
        expect(await repository.isInstalled('model__lora.bin'), isTrue);
        // The colliding plain key must NOT be the one that got registered.
        expect(await repository.isInstalled('lora.bin'), isFalse);
      },
    );

    test(
      'EmbeddingInstallationBuilder namespaces the tokenizer by the model',
      () async {
        await ServiceRegistry.initialize();

        final modelFile = File(
          path.join(sourceDir.path, 'Gecko_64_quant.tflite'),
        );
        await modelFile.writeAsBytes(_fakeModelBytes);
        final tokenizerFile = File(
          path.join(sourceDir.path, 'sentencepiece.model'),
        );
        await tokenizerFile.writeAsBytes(_fakeCompanionBytes);

        await FlutterGemma.installEmbedder()
            .modelFromFile(modelFile.path)
            .tokenizerFromFile(tokenizerFile.path)
            .install();

        final repository = ServiceRegistry.instance.modelRepository;
        expect(await repository.isInstalled('Gecko_64_quant.tflite'), isTrue);
        expect(
          await repository.isInstalled('Gecko_64_quant__sentencepiece.model'),
          isTrue,
        );
        expect(await repository.isInstalled('sentencepiece.model'), isFalse);
      },
    );

    test(
      'SttInstallationBuilder namespaces the tokenizer by the model',
      () async {
        await ServiceRegistry.initialize();

        final modelFile = File(
          path.join(sourceDir.path, 'moonshine_tiny_5s_f32.tflite'),
        );
        await modelFile.writeAsBytes(_fakeModelBytes);
        final tokenizerFile = File(path.join(sourceDir.path, 'tokenizer.json'));
        await tokenizerFile.writeAsBytes(_fakeCompanionBytes);

        await FlutterGemma.installStt()
            .modelFromFile(modelFile.path)
            .tokenizerFromFile(tokenizerFile.path)
            .ofType(SttModelType.moonshine)
            .install();

        final repository = ServiceRegistry.instance.modelRepository;
        expect(
          await repository.isInstalled('moonshine_tiny_5s_f32.tflite'),
          isTrue,
        );
        expect(
          await repository.isInstalled('moonshine_tiny_5s_f32__tokenizer.json'),
          isTrue,
        );
        expect(await repository.isInstalled('tokenizer.json'), isFalse);
      },
    );

    test('TtsInstallationBuilder writes every bundle file under its namespaced '
        'name on disk (not just the isInstalled key)', () async {
      final fixtureDownload = _FixtureDownloadService(_fakeCompanionBytes);
      await ServiceRegistry.initialize(downloadService: fixtureDownload);

      await FlutterGemma.installTts()
          .fromNetwork('https://example.com/matcha/')
          .ofType(TtsModelType.matcha)
          .install();

      final repository = ServiceRegistry.instance.modelRepository;
      expect(
        await repository.isInstalled('matcha__matcha_textenc_fp16.tflite'),
        isTrue,
      );
      expect(await repository.isInstalled('matcha__config.json'), isTrue);
      // Written under the NAMESPACED name in the actual model storage dir —
      // not the plain manifest name (that was the bug this task fixes:
      // before the targetFilename fix, the repository key was namespaced
      // but the physical write stayed on the plain basename). Resolve the
      // storage dir via the same FileSystemService the builder used rather
      // than hardcoding fakeDocuments.path — on desktop hosts (this test
      // typically runs as a native VM test) writes land under
      // ApplicationSupport/flutter_gemma/, not Documents; on mobile they
      // land directly under Documents.
      final storageDir = await ServiceRegistry.instance.fileSystemService
          .getModelStorageDirectory();
      expect(
        File(path.join(storageDir, 'matcha__config.json')).existsSync(),
        isTrue,
      );
      expect(File(path.join(storageDir, 'config.json')).existsSync(), isFalse);
    });
  });

  group('Task 5: restore-on-launch reads the namespaced identity', () {
    test(
      'MobileModelManager restores the active TTS model with the correct '
      'namespaced filenames after install (simulating an app relaunch)',
      () async {
        final fixtureDownload = _FixtureDownloadService(_fakeCompanionBytes);
        await ServiceRegistry.initialize(downloadService: fixtureDownload);

        await FlutterGemma.installTts()
            .fromNetwork('https://example.com/matcha/')
            .ofType(TtsModelType.matcha)
            .install();

        // A fresh manager instance has never restored anything yet — this
        // exercises _restoreActiveTtsModel from a cold start, exactly like
        // a real app relaunch.
        final freshManager = MobileModelManager();
        await freshManager.initialize();

        final restored = freshManager.activeTtsModel;
        expect(restored, isNotNull);
        expect(restored!.type, ModelManagementType.tts);
        // The restored spec's OWN .files getter must reproduce the SAME
        // namespaced filenames as install time — no double-prefix
        // (matcha__matcha__config.json) and no missing prefix (config.json).
        final configFile = restored.files.firstWhere(
          (f) => f.prefsKey == 'config.json',
        );
        expect(configFile.filename, 'matcha__config.json');
      },
    );
  });

  group('Task 6: migration fallback-probe (unique-basename files only)', () {
    test(
      'an old flat TTS bundle file is adopted in place — no re-download',
      () async {
        final fixtureDownload = _FixtureDownloadService(_fakeCompanionBytes);
        await ServiceRegistry.initialize(downloadService: fixtureDownload);

        // Resolve the storage dir via the same FileSystemService the
        // builder/adopt probe use rather than hardcoding fakeDocuments.path
        // — on desktop hosts (this test typically runs as a native VM test)
        // writes land under ApplicationSupport/flutter_gemma/, not
        // Documents; on mobile they land directly under Documents.
        final storageDir = await ServiceRegistry.instance.fileSystemService
            .getModelStorageDirectory();

        // Pre-seed ONE bundle member at its OLD, pre-refactor flat path —
        // simulating a matcha install from before this refactor shipped.
        final oldPath = path.join(storageDir, 'matcha_textenc_fp16.tflite');
        await File(oldPath).writeAsBytes([7, 7, 7, 7]);

        await FlutterGemma.installTts()
            .fromNetwork('https://example.com/matcha/')
            .ofType(TtsModelType.matcha)
            .install();

        // Adopted in place: old path gone, new namespaced path holds the
        // ORIGINAL bytes (proves it was renamed, not re-downloaded — a
        // re-download would have overwritten it with _fakeCompanionBytes).
        expect(await File(oldPath).exists(), isFalse);
        final newPath = path.join(
          storageDir,
          'matcha__matcha_textenc_fp16.tflite',
        );
        expect(await File(newPath).readAsBytes(), [7, 7, 7, 7]);
        expect(
          fixtureDownload.requestedTargetPaths.contains(newPath),
          isFalse,
          reason: 'the adopted file must not have been (re-)downloaded',
        );

        // Every OTHER bundle member (no old file seeded) was downloaded
        // normally under its namespaced name.
        final otherPath = path.join(storageDir, 'matcha__config.json');
        expect(
          fixtureDownload.requestedTargetPaths.contains(otherPath),
          isTrue,
        );

        final repository = ServiceRegistry.instance.modelRepository;
        expect(
          await repository.isInstalled('matcha__matcha_textenc_fp16.tflite'),
          isTrue,
        );
      },
    );

    test(
      'a colliding companion (tokenizer) NEVER triggers migration — it always '
      'installs fresh under the namespaced key (the mis-adoption guard)',
      () async {
        await ServiceRegistry.initialize();

        // Pre-seed an old flat tokenizer.json at the REAL storage location
        // (see storageDir note above) — this must be IGNORED, not adopted,
        // because a plain tokenizer.json on disk could belong to ANY
        // previously-installed STT/embedding model.
        final storageDir = await ServiceRegistry.instance.fileSystemService
            .getModelStorageDirectory();
        final oldTokenizerPath = path.join(storageDir, 'tokenizer.json');
        await File(oldTokenizerPath).writeAsBytes([9, 9, 9]);

        final modelFile = File(
          path.join(sourceDir.path, 'moonshine_tiny_5s_f32.tflite'),
        );
        await modelFile.writeAsBytes(_fakeModelBytes);
        final tokenizerFile = File(path.join(sourceDir.path, 'tokenizer.json'));
        await tokenizerFile.writeAsBytes(_fakeCompanionBytes);

        await FlutterGemma.installStt()
            .modelFromFile(modelFile.path)
            .tokenizerFromFile(tokenizerFile.path)
            .ofType(SttModelType.moonshine)
            .install();

        // The stale flat file is untouched — proof no migration/adoption
        // logic ever ran against it.
        expect(await File(oldTokenizerPath).readAsBytes(), [9, 9, 9]);

        final repository = ServiceRegistry.instance.modelRepository;
        expect(
          await repository.isInstalled('moonshine_tiny_5s_f32__tokenizer.json'),
          isTrue,
        );
      },
    );
  });

  group('Task 7: coexistence — the actual bug, end to end', () {
    test('installing moonshine THEN whisper keeps two distinct tokenizer '
        'files + two true isInstalled keys; neither silently reuses the '
        "other's file", () async {
      await ServiceRegistry.initialize();
      final repository = ServiceRegistry.instance.modelRepository;

      final moonshineModel = File(
        path.join(sourceDir.path, 'moonshine_tiny_5s_f32.tflite'),
      );
      await moonshineModel.writeAsBytes(_fakeModelBytes);
      final moonshineTokenizer = File(
        path.join(sourceDir.path, 'moonshine_tokenizer.json'),
      );
      await moonshineTokenizer.writeAsBytes(
        Uint8List.fromList(List.filled(2048, 1)),
      );

      await FlutterGemma.installStt()
          .modelFromFile(moonshineModel.path)
          .tokenizerFromFile(moonshineTokenizer.path)
          .ofType(SttModelType.moonshine)
          .install();

      final whisperDir = await Directory.systemTemp.createTemp(
        'flutter_gemma_whisper_src_',
      );
      addTearDown(() => whisperDir.delete(recursive: true));
      final whisperModel = File(
        path.join(whisperDir.path, 'whisper_tiny_30s_f32.tflite'),
      );
      await whisperModel.writeAsBytes(_fakeModelBytes);
      // Both catalogs literally name this file 'tokenizer.json' — see
      // example/lib/models/stt_model.dart.
      final whisperTokenizer = File(
        path.join(whisperDir.path, 'tokenizer.json'),
      );
      await whisperTokenizer.writeAsBytes(
        Uint8List.fromList(List.filled(2048, 2)),
      );

      await FlutterGemma.installStt()
          .modelFromFile(whisperModel.path)
          .tokenizerFromFile(whisperTokenizer.path)
          .ofType(SttModelType.whisper)
          .install();

      expect(
        await repository.isInstalled(
          'moonshine_tiny_5s_f32__moonshine_tokenizer.json',
        ),
        isTrue,
      );
      expect(
        await repository.isInstalled('whisper_tiny_30s_f32__tokenizer.json'),
        isTrue,
      );
    });

    test(
      'installing embeddinggemma THEN Gecko keeps two distinct tokenizer '
      'files despite BOTH being sentencepiece.model AND BOTH '
      'ModelManagementType.embedding (the per-broad-type-would-fail case)',
      () async {
        await ServiceRegistry.initialize();
        final repository = ServiceRegistry.instance.modelRepository;

        final gemmaModel = File(
          path.join(
            sourceDir.path,
            'embeddinggemma-300M_seq1024_mixed-precision.tflite',
          ),
        );
        await gemmaModel.writeAsBytes(_fakeModelBytes);
        final gemmaTokenizer = File(
          path.join(sourceDir.path, 'sentencepiece.model'),
        );
        await gemmaTokenizer.writeAsBytes(
          Uint8List.fromList(List.filled(2048, 3)),
        );

        await FlutterGemma.installEmbedder()
            .modelFromFile(gemmaModel.path)
            .tokenizerFromFile(gemmaTokenizer.path)
            .install();

        final geckoDir = await Directory.systemTemp.createTemp(
          'flutter_gemma_gecko_src_',
        );
        addTearDown(() => geckoDir.delete(recursive: true));
        final geckoModel = File(
          path.join(geckoDir.path, 'Gecko_64_quant.tflite'),
        );
        await geckoModel.writeAsBytes(_fakeModelBytes);
        final geckoTokenizer = File(
          path.join(geckoDir.path, 'sentencepiece.model'),
        );
        await geckoTokenizer.writeAsBytes(
          Uint8List.fromList(List.filled(2048, 4)),
        );

        await FlutterGemma.installEmbedder()
            .modelFromFile(geckoModel.path)
            .tokenizerFromFile(geckoTokenizer.path)
            .install();

        expect(
          await repository.isInstalled(
            'embeddinggemma-300M_seq1024_mixed-precision__sentencepiece.model',
          ),
          isTrue,
        );
        expect(
          await repository.isInstalled('Gecko_64_quant__sentencepiece.model'),
          isTrue,
        );
      },
    );
  });
}

/// PathProviderPlatform stub that returns fixed, distinct paths for
/// Documents and ApplicationSupport so tests can distinguish them (mirrors
/// test/core/api/stt_install_plumbing_test.dart).
class _FixedPathProviderPlatform extends PathProviderPlatform {
  final String documentsPath;
  final String appSupportPath;

  _FixedPathProviderPlatform({
    required this.documentsPath,
    required this.appSupportPath,
  });

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String?> getApplicationSupportPath() async => appSupportPath;

  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

/// A real (non-mock) DownloadService fake that writes [bytes] to whatever
/// targetPath it's asked to download to, instead of making a real HTTP
/// request. Tracks every requested target path so tests can assert exactly
/// which files were (re-)downloaded vs adopted via migration (Task 6/7).
class _FixtureDownloadService implements DownloadService {
  final Uint8List bytes;
  final List<String> requestedTargetPaths = [];
  _FixtureDownloadService(this.bytes);

  @override
  Future<void> download(
    String url,
    String targetPath, {
    String? token,
    CancelToken? cancelToken,
  }) async {
    requestedTargetPaths.add(targetPath);
    await File(targetPath).writeAsBytes(bytes);
  }

  @override
  Stream<int> downloadWithProgress(
    String url,
    String targetPath, {
    String? token,
    int maxRetries = 10,
    CancelToken? cancelToken,
    bool? foreground,
  }) async* {
    requestedTargetPaths.add(targetPath);
    await File(targetPath).writeAsBytes(bytes);
    yield 100;
  }
}
