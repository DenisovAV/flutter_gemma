// #500: `getActiveStt(language:)` must take effect on EVERY call, not just the
// first one in a process.
//
// The STT singleton cache (FlutterGemmaMobile.createSttModel) keys its "reuse
// the existing recognizer" branch on the active model's name. The first fix for
// #500 added a `language` parameter and stopped there, so the second
// `getActiveStt(language: 'de')` for the same active model returned the
// recognizer built for the FIRST language and transcribed into it — no error,
// no log in release, and a fluent English translation of German audio, which is
// indistinguishable from success.
//
// That is the same shape the TTS path already had and already fixed; see
// tts_language_singleton_test.dart, whose fixtures this file mirrors. TTS chose
// to fail loud (throw, close first). STT does not have to: Whisper's decoder
// prompt is rebuilt per transcription, so the language is a settable property
// on the recognizer and retargeting costs nothing. This test pins THAT — the
// recognizer is reused, not rebuilt, and its language follows the request.
//
// A real end-to-end test against the ACTUAL FlutterGemmaMobile/FlutterGemma
// facade, not a simulation of the completer logic — the bug lived in the shell,
// so a test that reimplements the shell would have passed while shipping it.
//
// Run: flutter test test/mobile/stt_language_singleton_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/registry/stt_backend_provider.dart';
import 'package:flutter_gemma/core/registry/stt_registry.dart';
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// FileSourceHandler enforces a per-extension minimum size; this clears both the
// 1KB (json) and 1MB (tflite) floors with one fixture.
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
    SttRegistry.instance.reset();
  });

  tearDown(() async {
    ServiceRegistry.reset();
    SttRegistry.instance.reset();
    for (final dir in [fakeDocuments, fakeAppSupport]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  });

  Future<_FakeSttBackend> installWhisper() async {
    await ServiceRegistry.initialize(
      downloadService: _FixtureDownloadService(_fakeBundleBytes),
    );
    final backend = _FakeSttBackend();
    SttRegistry.instance.registerAll([backend]);

    await FlutterGemma.installStt()
        .modelFromNetwork('https://example.com/whisper.tflite')
        .tokenizerFromNetwork('https://example.com/tokenizer.json')
        .ofType(SttModelType.whisper)
        .install();

    return backend;
  }

  test('language reaches RuntimeConfig on the first call', () async {
    // The ORIGINAL #500 bug: the parameter existed on four signatures and was
    // dropped before RuntimeConfig, so it compiled, ran, and did nothing. Any
    // shell that stops forwarding it fails here.
    final backend = await installWhisper();

    final recognizer = await FlutterGemma.getActiveStt(language: 'de');

    expect(backend.lastConfig?.language, 'de');
    expect(backend.createModelCallCount, 1);
    expect(recognizer.language, 'de');

    await recognizer.close();
  });

  test('a second call with a DIFFERENT language retargets the same '
      'recognizer instead of silently reusing the first language', () async {
    final backend = await installWhisper();

    final first = await FlutterGemma.getActiveStt(language: 'en');
    expect(first.language, 'en');
    expect(backend.createModelCallCount, 1);

    final second = await FlutterGemma.getActiveStt(language: 'de');

    // The singleton is REUSED — no reload, no isolate respawn, and the caller's
    // existing handle is not closed underneath them.
    expect(identical(second, first), isTrue);
    expect(backend.createModelCallCount, 1);

    // …and it now speaks German. This is the assertion the shipped code failed:
    // before the fix `second.language` was still 'en'.
    expect(second.language, 'de');
    expect(first.language, 'de', reason: 'same object, so it must agree');

    await first.close();
  });

  test('a later call with no language clears the override back to the '
      "model's own default", () async {
    // `null` must mean "the model's default", not "keep whatever was last set".
    // A guard written as `if (language != null) cached.language = language`
    // would strand a caller who explicitly asked to go back to the default.
    final backend = await installWhisper();

    final recognizer = await FlutterGemma.getActiveStt(language: 'de');
    expect(recognizer.language, 'de');

    final again = await FlutterGemma.getActiveStt();

    expect(identical(again, recognizer), isTrue);
    expect(again.language, isNull);
    expect(backend.createModelCallCount, 1);

    await recognizer.close();
  });

  test(
    'the per-call override on transcribe does not disturb the default',
    () async {
      final backend = await installWhisper();

      final recognizer = await FlutterGemma.getActiveStt(language: 'de');
      await recognizer.transcribe(Uint8List(16), language: 'fr');

      expect(backend.recognizer.lastTranscribeLanguage, 'fr');
      // A per-call value that leaked into the default would make the NEXT call
      // French too — the same stale-state class of bug, one layer down.
      expect(recognizer.language, 'de');

      await recognizer.transcribe(Uint8List(16));
      expect(backend.recognizer.lastTranscribeLanguage, 'de');

      await recognizer.close();
    },
  );
}

class _FakeSttBackend implements SttBackendProvider {
  RuntimeConfig? lastConfig;
  int createModelCallCount = 0;
  late _FakeSpeechRecognizer recognizer;

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
    createModelCallCount++;
    lastConfig = config;
    return recognizer = _FakeSpeechRecognizer(config.language);
  }
}

/// Stands in for `LiteRtSpeechRecognizer`, reproducing the one behaviour under
/// test: `language` is mutable state consulted per `transcribe`, with the
/// per-call argument winning.
class _FakeSpeechRecognizer extends SpeechRecognizer with CloseNotifier {
  _FakeSpeechRecognizer(this.language);

  @override
  String? language;

  String? lastTranscribeLanguage;

  @override
  Future<String> transcribe(Uint8List pcm16kMono, {String? language}) async {
    lastTranscribeLanguage = language ?? this.language;
    return 'ok';
  }

  @override
  Future<void> close() async {
    fireCloseListeners();
  }
}

/// PathProviderPlatform stub returning fixed, distinct paths (mirrors
/// tts_language_singleton_test.dart).
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

/// Writes [bytes] to whatever targetPath it is asked for, instead of making a
/// real HTTP request.
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
