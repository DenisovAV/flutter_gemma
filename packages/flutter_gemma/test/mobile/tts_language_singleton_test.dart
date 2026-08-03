// Task 5.4 review, Important #1: the TTS singleton cache
// (FlutterGemmaMobile.createTtsModel) used to key its "reuse the existing
// synthesizer" branch ONLY on the active model's name, not on the requested
// `language`. So a second `getActiveTts(language: 'french')` for the SAME
// active qwen3 model silently returned the FIRST call's (e.g. English)
// synthesizer — wrong-language audio through the primary public API, with
// no error. This is a real end-to-end test against the ACTUAL
// FlutterGemmaMobile/FlutterGemma facade (not a hand-rolled simulation of
// the completer logic) — it uses the exact `_FixtureDownloadService` +
// `_FixedPathProviderPlatform` fixture pattern already established in
// test/core/api/install_identity_namespacing_test.dart to get a REAL
// install() + getActiveTts() flow working without a device or network.
//
// Run: flutter test test/mobile/tts_language_singleton_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/registry/tts_backend_provider.dart';
import 'package:flutter_gemma/core/registry/tts_registry.dart';
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// FileSourceHandler enforces a minimum size per extension — the qwen3
// manifest's 9 files clear both the 1KB (json/npy/npz) and 1MB (tflite)
// floors with this single fixture, mirroring the matcha fixture in
// install_identity_namespacing_test.dart.
final _fakeBundleBytes = Uint8List(1024 * 1024 + 16);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory fakeDocuments;
  late Directory fakeAppSupport;

  setUp(() async {
    fakeDocuments = await Directory.systemTemp.createTemp(
      'flutter_gemma_docs_',
    );
    fakeAppSupport = await Directory.systemTemp.createTemp(
      'flutter_gemma_appsupport_',
    );
    PathProviderPlatform.instance = _FixedPathProviderPlatform(
      documentsPath: fakeDocuments.path,
      appSupportPath: fakeAppSupport.path,
    );
    SharedPreferences.setMockInitialValues({});
    ServiceRegistry.reset();
    TtsRegistry.instance.reset();
  });

  tearDown(() async {
    ServiceRegistry.reset();
    TtsRegistry.instance.reset();
    for (final dir in [fakeDocuments, fakeAppSupport]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  });

  test('getActiveTts throws StateError (not a silent wrong-language reuse) '
      'when a second call requests a different language for the same active '
      'model, without closing the first synthesizer', () async {
    final fixtureDownload = _FixtureDownloadService(_fakeBundleBytes);
    await ServiceRegistry.initialize(downloadService: fixtureDownload);
    final fakeBackend = _FakeTtsBackend();
    TtsRegistry.instance.registerAll([fakeBackend]);

    await FlutterGemma.installTts()
        .fromNetwork('https://example.com/qwen3/')
        .ofType(TtsModelType.qwen3)
        .install();

    final synth1 = await FlutterGemma.getActiveTts(language: 'english');
    expect(fakeBackend.lastConfig?.language, 'english');
    expect(fakeBackend.createModelCallCount, 1);

    // Same language again -> reuses the singleton (no new backend call,
    // no error) — the guard must not be overly strict.
    final synth1Again = await FlutterGemma.getActiveTts(language: 'english');
    expect(identical(synth1Again, synth1), isTrue);
    expect(fakeBackend.createModelCallCount, 1);

    // Different language, SAME active model, WITHOUT closing first ->
    // must fail loud. Before the fix this returned synth1 (English)
    // silently; after the fix it throws instead.
    await expectLater(
      FlutterGemma.getActiveTts(language: 'french'),
      throwsA(isA<StateError>()),
    );
    // The rejected request must not have built a second synthesizer —
    // this is a fail-FAST guard, not a fallback that still constructs
    // something wrong.
    expect(fakeBackend.createModelCallCount, 1);

    // After the caller closes the existing synthesizer, a new language is
    // allowed and actually rebuilds against the new language.
    await synth1.close();
    final synth2 = await FlutterGemma.getActiveTts(language: 'french');
    expect(fakeBackend.lastConfig?.language, 'french');
    expect(fakeBackend.createModelCallCount, 2);
    expect(identical(synth2, synth1), isFalse);
  });
}

class _FakeTtsBackend implements TtsBackendProvider {
  RuntimeConfig? lastConfig;
  int createModelCallCount = 0;

  @override
  String get name => 'FakeTTS';

  @override
  int get priority => 0;

  @override
  bool canHandle(TtsModelSpec spec) => true;

  @override
  Future<SpeechSynthesizer> createModel(
    TtsModelSpec spec,
    RuntimeConfig config,
  ) async {
    createModelCallCount++;
    lastConfig = config;
    return _FakeSpeechSynthesizer();
  }
}

class _FakeSpeechSynthesizer extends SpeechSynthesizer with CloseNotifier {
  @override
  int get sampleRate => 24000;

  @override
  Future<Uint8List> synthesize(String text) async => Uint8List(4);

  @override
  Future<void> close() async {
    fireCloseListeners();
  }
}

/// PathProviderPlatform stub that returns fixed, distinct paths for
/// Documents and ApplicationSupport (mirrors
/// test/core/api/install_identity_namespacing_test.dart).
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
/// request (mirrors install_identity_namespacing_test.dart's
/// _FixtureDownloadService).
class _FixtureDownloadService implements DownloadService {
  final Uint8List bytes;
  _FixtureDownloadService(this.bytes);

  @override
  Future<void> download(
    String url,
    String targetPath, {
    String? token,
    CancelToken? cancelToken,
  }) async {
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
    await File(targetPath).writeAsBytes(bytes);
    yield 100;
  }
}
