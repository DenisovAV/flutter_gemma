// Unit test for the core STT install/get plumbing (Task 2.1).
//
// Mirrors the embedder path: FlutterGemma.installStt()
// .modelFromFile(...).tokenizerFromFile(...).ofType(...).install() sets an
// active SttModelSpec, hasActiveStt() flips true, and getActiveStt()
// dispatches through the SttRegistry to the registered backend, returning
// its SpeechRecognizer.
//
// Run: flutter test test/core/api/stt_install_plumbing_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/registry/stt_backend_provider.dart';
import 'package:flutter_gemma/core/registry/stt_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// FileSourceHandler enforces a minimum size per extension (1MB for model
// files, 1KB for small/config extensions like .json) to catch truncated
// downloads (see FileNameUtils.getMinimumSize) — the fixtures below must
// clear both thresholds or "install" rejects them as corrupted.
final _fakeModelBytes = Uint8List(1024 * 1024 + 16);
final _fakeTokenizerBytes = Uint8List(2048);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fakeDocuments;
  late Directory fakeAppSupport;
  late Directory sourceDir;
  late _FixedPathProviderPlatform mockProvider;

  setUp(() async {
    fakeDocuments = await Directory.systemTemp.createTemp(
      'flutter_gemma_docs_',
    );
    fakeAppSupport = await Directory.systemTemp.createTemp(
      'flutter_gemma_appsupport_',
    );
    sourceDir = await Directory.systemTemp.createTemp('flutter_gemma_src_');
    mockProvider = _FixedPathProviderPlatform(
      documentsPath: fakeDocuments.path,
      appSupportPath: fakeAppSupport.path,
    );
    PathProviderPlatform.instance = mockProvider;
    SharedPreferences.setMockInitialValues({});
    ServiceRegistry.reset();
    SttRegistry.instance.reset();
    // The default FlutterGemmaPlugin instance (and its model manager) is a
    // process-wide singleton that outlives each test — clear any active STT
    // identity a previous test left behind so tests stay independent.
    await FlutterGemmaPlugin.instance.modelManager.clearActiveSttIdentity();
  });

  tearDown(() async {
    ServiceRegistry.reset();
    SttRegistry.instance.reset();
    for (final dir in [fakeDocuments, fakeAppSupport, sourceDir]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  });

  group('STT install/get plumbing', () {
    test(
      'installStt().ofType().install() sets active spec; getActiveStt() dispatches to the registered backend',
      () async {
        final fakeBackend = _FakeSttBackend();
        await FlutterGemma.initialize(sttBackends: [fakeBackend]);

        final modelFile = File(path.join(sourceDir.path, 'model.tflite'));
        await modelFile.writeAsBytes(_fakeModelBytes);
        final tokenizerFile = File(path.join(sourceDir.path, 'tokenizer.json'));
        await tokenizerFile.writeAsBytes(_fakeTokenizerBytes);

        final installation = await FlutterGemma.installStt()
            .modelFromFile(modelFile.path)
            .tokenizerFromFile(tokenizerFile.path)
            .ofType(SttModelType.moonshine)
            .install();

        expect(installation.spec.sttModelType, SttModelType.moonshine);
        expect(installation.spec, isA<SttModelSpec>());

        expect(FlutterGemma.hasActiveStt(), isTrue);

        final recognizer = await FlutterGemma.getActiveStt();
        expect(recognizer, isA<_FakeSpeechRecognizer>());
        expect(fakeBackend.lastSpec?.sttModelType, SttModelType.moonshine);
        expect(fakeBackend.lastConfig?.modelPath, isNotEmpty);
        expect(fakeBackend.lastConfig?.tokenizerPath, isNotEmpty);
      },
    );

    test('installStt().install() without ofType() throws StateError', () async {
      await FlutterGemma.initialize(sttBackends: [_FakeSttBackend()]);

      final modelFile = File(path.join(sourceDir.path, 'model.tflite'));
      await modelFile.writeAsBytes(_fakeModelBytes);
      final tokenizerFile = File(path.join(sourceDir.path, 'tokenizer.json'));
      await tokenizerFile.writeAsBytes(_fakeTokenizerBytes);

      expect(
        () => FlutterGemma.installStt()
            .modelFromFile(modelFile.path)
            .tokenizerFromFile(tokenizerFile.path)
            .install(),
        throwsStateError,
      );
    });

    test('getActiveStt() throws when no active STT model is set', () async {
      await FlutterGemma.initialize(sttBackends: [_FakeSttBackend()]);
      expect(FlutterGemma.hasActiveStt(), isFalse);
      expect(() => FlutterGemma.getActiveStt(), throwsStateError);
    });
  });
}

class _FakeSttBackend implements SttBackendProvider {
  SttModelSpec? lastSpec;
  RuntimeConfig? lastConfig;

  @override
  String get name => 'FakeSTT';

  @override
  int get priority => 0;

  @override
  bool canHandle(SttModelSpec spec) => true;

  @override
  Future<SpeechRecognizer> createModel(
    SttModelSpec spec,
    RuntimeConfig config,
  ) async {
    lastSpec = spec;
    lastConfig = config;
    return _FakeSpeechRecognizer();
  }
}

class _FakeSpeechRecognizer extends SpeechRecognizer with CloseNotifier {
  @override
  Future<String> transcribe(Uint8List pcm16kMono) async => 'fake transcript';

  @override
  Future<void> close() async {
    fireCloseListeners();
  }
}

/// PathProviderPlatform stub that returns fixed, distinct paths for
/// Documents and ApplicationSupport so tests can distinguish them.
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
