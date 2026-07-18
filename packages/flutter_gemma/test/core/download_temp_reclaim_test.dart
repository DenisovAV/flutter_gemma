import 'package:flutter_gemma/core/model_management/utils/download_temp_reclaim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dir = '/data/data/app/files';
  String p(String name) => '$dir/$name';
  const old = Duration(minutes: 30);
  const fresh = Duration(minutes: 2);

  group('shouldReclaimDownloadTemp (#383)', () {
    test('deletes an old, unreferenced background_downloader temp', () {
      expect(
        shouldReclaimDownloadTemp(
          basename: 'com.bbflight.background_downloader123456',
          path: p('com.bbflight.background_downloader123456'),
          keepPaths: const {},
          age: old,
        ),
        isTrue,
      );
    });

    test('keeps a non-background_downloader file (a real model)', () {
      expect(
        shouldReclaimDownloadTemp(
          basename: 'gemma-4-E2B-it.litertlm',
          path: p('gemma-4-E2B-it.litertlm'),
          keepPaths: const {},
          age: old,
        ),
        isFalse,
      );
    });

    test('keeps a temp referenced by a valid pending resume (keep-set)', () {
      final path = p('com.bbflight.background_downloader999');
      expect(
        shouldReclaimDownloadTemp(
          basename: 'com.bbflight.background_downloader999',
          path: path,
          keepPaths: {path},
          age: old,
        ),
        isFalse,
      );
    });

    test('keeps a FRESH temp — mtime guard is "older than", never delete a '
        'possibly-live download (the architect-flagged direction)', () {
      expect(
        shouldReclaimDownloadTemp(
          basename: 'com.bbflight.background_downloader777',
          path: p('com.bbflight.background_downloader777'),
          keepPaths: const {},
          age: fresh,
        ),
        isFalse,
      );
    });

    test('deletes exactly at the age boundary (>= minAge deletes)', () {
      // age == minAge is not "< minAge", so it is reclaimable.
      expect(
        shouldReclaimDownloadTemp(
          basename: 'com.bbflight.background_downloader1',
          path: p('com.bbflight.background_downloader1'),
          keepPaths: const {},
          age: kDownloadTempMinReclaimAge,
        ),
        isTrue,
      );
      // One tick younger is spared.
      expect(
        shouldReclaimDownloadTemp(
          basename: 'com.bbflight.background_downloader1',
          path: p('com.bbflight.background_downloader1'),
          keepPaths: const {},
          age: kDownloadTempMinReclaimAge - const Duration(seconds: 1),
        ),
        isFalse,
      );
    });
  });
}
