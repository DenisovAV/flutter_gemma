/// On-device validation of the #383 orphaned-download-temp reclaim.
///
/// The pure predicate is unit-tested off-device; what only a real Android device
/// can confirm is the INTEGRATION: that `getApplicationSupportDirectory()`
/// resolves to the same `filesDir` where `background_downloader` writes
/// large-file temps, that the sweep enumerates + deletes there, and that a real
/// download's temp actually lands in that directory.
///
/// Run (Android device / FTL):
///   flutter test integration_test/download_temp_reclaim_device_test.dart -d <android>
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/core/model_management/utils/download_temp_reclaim.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'inference_test_helpers.dart' show registerTestEngines;

const _gemma4Url =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _token = String.fromEnvironment('HUGGINGFACE_TOKEN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await registerTestEngines();
  });

  // ── A. The sweep on a REAL Android filesDir ──────────────────────────────
  testWidgets(
    'A: getApplicationSupportDirectory is filesDir and the sweep deletes '
    'orphaned temps there, keeping the keep-set and non-temp files',
    (tester) async {
      expect(Platform.isAndroid, isTrue, reason: 'device test is Android-only');

      final dir = await getApplicationSupportDirectory();
      print('[reclaim] applicationSupport = ${dir.path}');
      // Android filesDir is under the app data dir (…/files), never external.
      expect(dir.path.contains('/files'), isTrue, reason: 'expected filesDir');

      final orphan = File(
        p.join(dir.path, 'com.bbflight.background_downloader_TEST_orphan'),
      )..writeAsBytesSync(List.filled(1024, 0));
      final keep = File(
        p.join(dir.path, 'com.bbflight.background_downloader_TEST_keep'),
      )..writeAsBytesSync(List.filled(1024, 0));
      final model = File(p.join(dir.path, 'test_model_TEST.litertlm'))
        ..writeAsBytesSync(List.filled(1024, 0));

      addTearDown(() {
        for (final f in [orphan, keep, model]) {
          if (f.existsSync()) f.deleteSync();
        }
      });

      // minAge: 0 so the just-written synthetic temps are eligible (the
      // "older-than" mtime guard itself is covered by the off-device unit test).
      final reclaimed = await sweepOrphanedDownloadTemps(
        dir,
        keepPaths: {keep.path},
        minAge: Duration.zero,
      );

      print('[reclaim] deleted $reclaimed file(s)');
      expect(
        orphan.existsSync(),
        isFalse,
        reason: 'orphan temp must be deleted',
      );
      expect(keep.existsSync(), isTrue, reason: 'keep-set temp must survive');
      expect(model.existsSync(), isTrue, reason: 'a real model must survive');
      expect(reclaimed, greaterThanOrEqualTo(1));
    },
  );

  // ── B. A real download's temp lands in that same directory ───────────────
  testWidgets(
    'B: a live background_downloader partial for a 2.4GB model appears as a '
    'com.bbflight.background_downloader* temp in getApplicationSupportDirectory',
    (tester) async {
      if (_token.isEmpty) {
        markTestSkipped(
          'HUGGINGFACE_TOKEN not provided — skipping the real-download temp '
          'location check (Test A already validates the sweep on real filesDir; '
          "the location is also confirmed by #383's own logcat).",
        );
        return;
      }
      final dir = await getApplicationSupportDirectory();

      bool hasBgTemp() => dir
          .listSync(followLinks: false)
          .any(
            (e) =>
                e is File && p.basename(e.path).startsWith(kDownloadTempPrefix),
          );

      final cancel = CancelToken();
      // Fire the download; don't await — we only need it to START writing its
      // temp. Swallow the cancellation/other errors.
      unawaited(() async {
        try {
          await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
              .fromNetwork(_gemma4Url, token: _token)
              .withCancelToken(cancel)
              .withProgress((_) {})
              .install();
        } catch (_) {
          // Cancellation / network error — expected; we only wanted the temp.
        }
      }());

      // Poll up to ~90s for the native worker to create the temp.
      var appeared = false;
      for (var i = 0; i < 45 && !appeared; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        appeared = hasBgTemp();
      }
      cancel.cancel();
      await Future<void>.delayed(const Duration(seconds: 2));

      print('[reclaim] live download temp seen in filesDir: $appeared');
      expect(
        appeared,
        isTrue,
        reason:
            'a 2.4GB download must create a com.bbflight.background_downloader* '
            'temp in getApplicationSupportDirectory() — that is exactly the dir '
            'the reclaim sweep scans',
      );

      // Best-effort cleanup of any partial we just created.
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File && p.basename(e.path).startsWith(kDownloadTempPrefix)) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    },
  );
}
