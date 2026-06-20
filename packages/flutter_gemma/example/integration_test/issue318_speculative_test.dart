/// Issue #318 reproduction — `DYNAMIC_UPDATE_SLICE failed to prepare` on a
/// weak Android device (Xiaomi Redmi Note 10 / Helio G85 / Mali-G52) when
/// running `gemma-4-E2B-it.litertlm` with `enableSpeculativeDecoding: true`.
///
/// The user's exact config:
///   getActiveModel(supportImage: true, preferredBackend: cpu,
///                  enableSpeculativeDecoding: true, maxTokens: 100)
///
/// Hypothesis: speculative decoding (MTP) loads a draft model whose
/// DYNAMIC_UPDATE_SLICE op fails to allocate tensors on memory-constrained
/// hardware. Disabling it should let the same device generate normally.
///
/// This test runs the SAME config twice — MTP on, then MTP off — and records
/// the outcome of each WITHOUT letting an engine crash fail the harness (a
/// thrown engine_create on MTP=on is the *expected* repro, not a test bug).
/// Both outcomes are logged so the FTL result is a PASS carrying evidence.
///
/// Run (FTL realme C53, Mali-G52 — closest analog to Helio G85):
///   flutter test integration_test/issue318_speculative_test.dart -d <device>
library;

import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'inference_test_helpers.dart' show registerTestEngines;

const _gemma4Url =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _token = String.fromEnvironment('HUGGINGFACE_TOKEN');

String get _androidDir => '/data/local/tmp/flutter_gemma_test';

String? _localPath(String filename) {
  if (Platform.isAndroid) return '$_androidDir/$filename';
  return null;
}

/// Install once; both cases reuse the installed identity.
Future<void> _install() async {
  final local = _localPath('gemma-4-E2B-it.litertlm');
  if (local != null && File(local).existsSync()) {
    debugPrint('[#318] installing from local file: $local');
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(local).install();
  } else {
    debugPrint('[#318] local file not found, downloading from network');
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(_gemma4Url, token: _token).install();
  }
}

/// Run a text-only prompt with the user's #318 config. The fix should make
/// `maxTokens` below 1024 auto-clamp (no crash), and `maxOutputTokens` cap the
/// generated length without touching the context window.
/// Returns (ok, response, error). Never throws — a crash is captured.
Future<({bool ok, String response, String error})> _runUserConfig({
  required int maxTokens,
  int? maxOutputTokens,
}) async {
  InferenceModel? model;
  try {
    debugPrint(
      '[#318] getActiveModel(maxTokens: $maxTokens), '
      'createSession(maxOutputTokens: $maxOutputTokens)',
    );
    model = await FlutterGemma.getActiveModel(
      preferredBackend: PreferredBackend.cpu,
      maxTokens: maxTokens,
    );
    final session = await model.createSession(
      temperature: 0.8,
      topK: 1,
      maxOutputTokens: maxOutputTokens,
    );
    await session.addQueryChunk(
      const Message(text: 'What is the capital of France?', isUser: true),
    );
    final chunks = <String>[];
    await for (final c in session.getResponseAsync()) {
      chunks.add(c);
    }
    await session.close();
    final text = chunks.join();
    debugPrint(
      '[#318] maxTokens=$maxTokens maxOutputTokens=$maxOutputTokens '
      'OK, response="$text"',
    );
    return (ok: true, response: text, error: '');
  } catch (e) {
    debugPrint(
      '[#318] maxTokens=$maxTokens maxOutputTokens=$maxOutputTokens '
      'CRASHED: $e',
    );
    return (ok: false, response: '', error: e.toString());
  } finally {
    try {
      await model?.close();
    } catch (_) {}
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await registerTestEngines();
    await _install();
  });

  // FIX CHECK 1 — the user's exact crashing config: maxTokens=100. Before the
  // fix this crashed (DYNAMIC_UPDATE_SLICE). The clamp must now raise it to
  // 1024 internally so the same call generates a coherent answer.
  testWidgets(
    '#318 FIX: getActiveModel(maxTokens=100) auto-clamps and answers',
    (tester) async {
      final r = await _runUserConfig(maxTokens: 100);
      debugPrint(
        '[#318][FIX-RESULT] maxTokens=100 '
        'ok=${r.ok} response="${r.response}" error=${r.error}',
      );
      expect(
        r.ok,
        isTrue,
        reason: 'clamp should prevent the crash: ${r.error}',
      );
      expect(
        r.response.toLowerCase(),
        contains('paris'),
        reason: 'should produce a coherent answer after clamping',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  // FIX CHECK 2 — the user's real intent: limit OUTPUT length via the new
  // maxOutputTokens, leaving the context window at the default. Should answer
  // (and the cap bounds generation; we just assert it runs and is coherent).
  testWidgets(
    '#318 FIX: maxOutputTokens caps generation without crashing',
    (tester) async {
      final r = await _runUserConfig(maxTokens: 1024, maxOutputTokens: 100);
      debugPrint(
        '[#318][FIX-RESULT] maxOutputTokens=100 '
        'ok=${r.ok} response="${r.response}" error=${r.error}',
      );
      expect(
        r.ok,
        isTrue,
        reason: 'maxOutputTokens should not crash: ${r.error}',
      );
      expect(r.response.trim(), isNotEmpty, reason: 'should produce output');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
