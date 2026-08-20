// #445: depending on flutter_gemma must not take background_downloader away
// from the host app.
//
// `FileDownloader().updates` is a SINGLE-SUBSCRIPTION controller
// (`var updates = StreamController<TaskUpdate>()` in base_downloader.dart).
// SmartDownloader used to listen to it — via `asBroadcastStream()`, which still
// takes the one subscription the process has — so any later
// `FileDownloader().updates.listen(...)` in the app or in another package threw
// "Bad state: Stream has already been listened to". Nothing in flutter_gemma
// failed; the HOST did, for a stream flutter_gemma had no business claiming.
//
// The fix routes our own group through `registerCallbacks(group:)`, which
// base_downloader consults BEFORE `updates.hasListener` — so we still see every
// update for our tasks, and the stream stays untouched for everyone else.
//
// A first cut of this file asserted only the NEGATIVE — that we no longer claim
// the stream — plus our own bookkeeping flag. Review deleted `registerCallbacks`
// outright, so the package received nothing at all and every download would hang
// forever, and all six tests still passed. Delivery is now asserted directly:
// `FileDownloader().downloaderForTesting` is a `@visibleForTesting` getter on the
// EXPORTED class, so an update can be driven through the real dispatcher without
// reaching into `src/`.
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    SmartDownloader.clearConfiguration();
    await FileDownloader().resetUpdates();
  });

  tearDown(() async {
    SmartDownloader.clearConfiguration();
    await FileDownloader().resetUpdates();
  });

  test('the host can still listen to FileDownloader().updates (#445)', () {
    // Exactly what every download path does first.
    final ours = SmartDownloader.debugResolveUpdatesStream().listen((_) {});
    addTearDown(ours.cancel);

    // And now the host app, or any other package, does what it is entitled to.
    // Before the fix this threw "Stream has already been listened to".
    StreamSubscription<TaskUpdate>? host;
    expect(
      () => host = FileDownloader().updates.listen((_) {}),
      returnsNormally,
      reason:
          'SmartDownloader consumed the single subscription on '
          'FileDownloader().updates, so the host app can no longer receive '
          'updates for its own downloads',
    );
    addTearDown(() => host?.cancel());
  });

  test('two concurrent downloads can both listen', () {
    // The old code needed asBroadcastStream precisely because concurrent
    // downloads each call listen(). Whatever replaces it must keep that.
    final stream = SmartDownloader.debugResolveUpdatesStream();
    final a = stream.listen((_) {});
    final b = stream.listen((_) {});
    addTearDown(a.cancel);
    addTearDown(b.cancel);
    expect(SmartDownloader.debugGroupFanOutIsLive, isTrue);
  });

  test('cancelling the last listener does not tear the fan-out down', () async {
    final only = SmartDownloader.debugResolveUpdatesStream().listen((_) {});
    await only.cancel();

    // Downloads come and go. A fan-out that closed itself here would leave the
    // registered callbacks writing into a closed controller, and the next
    // download would hang with no updates at all.
    expect(SmartDownloader.debugGroupFanOutIsLive, isTrue);
  });

  test('clearConfiguration releases it, and a later resolve rebuilds', () {
    SmartDownloader.debugResolveUpdatesStream().listen((_) {}).cancel();
    expect(SmartDownloader.debugGroupFanOutIsLive, isTrue);

    SmartDownloader.clearConfiguration();
    expect(
      SmartDownloader.debugGroupFanOutIsLive,
      isFalse,
      reason:
          'a host that disposes flutter_gemma should get its downloader back',
    );

    // And the next download must not be handed the closed controller.
    final stream = SmartDownloader.debugResolveUpdatesStream();
    final sub = stream.listen((_) {});
    addTearDown(sub.cancel);
    expect(SmartDownloader.debugGroupFanOutIsLive, isTrue);
  });

  test('an injected hub stream still wins over the group fan-out', () {
    // configureDownloadUpdatesStream is how a host forwards its own hub in.
    // The #445 fix must not have quietly bypassed it.
    final hub = StreamController<TaskUpdate>.broadcast();
    addTearDown(hub.close);
    // Capture once: `controller.stream` hands back a fresh view each call, so
    // comparing against a second `hub.stream` would fail for the wrong reason.
    final hubStream = hub.stream;
    SmartDownloader.configureDownloadUpdatesStream(hubStream);

    expect(
      identical(SmartDownloader.debugResolveUpdatesStream(), hubStream),
      isTrue,
    );
    expect(
      SmartDownloader.debugGroupFanOutIsLive,
      isFalse,
      reason: 'the group fan-out was built even though a hub was injected',
    );
  });

  test('an update for our group actually reaches our stream', () async {
    // THE mechanism test. Deleting registerCallbacks, or naming the wrong
    // group, or omitting taskProgressCallback, all fail here — and all of them
    // otherwise look like a download frozen at 0% until a 90s watchdog fires.
    final got = <TaskUpdate>[];
    final sub = SmartDownloader.debugResolveUpdatesStream().listen(got.add);
    addTearDown(sub.cancel);

    final base = FileDownloader().downloaderForTesting
      ..processStatusUpdate(TaskStatusUpdate(_ourTask(), TaskStatus.running))
      ..processProgressUpdate(TaskProgressUpdate(_ourTask(), 0.42));
    expect(base, isNotNull);
    await Future<void>.delayed(Duration.zero);

    expect(got, hasLength(2), reason: 'status and progress must BOTH arrive');
    expect(got.whereType<TaskProgressUpdate>().single.progress, 0.42);
  });

  test('our updates come to us, the host keeps its own', () async {
    final ours = <TaskUpdate>[];
    final host = <TaskUpdate>[];
    final a = SmartDownloader.debugResolveUpdatesStream().listen(ours.add);
    final b = FileDownloader().updates.listen(host.add);
    addTearDown(a.cancel);
    addTearDown(b.cancel);

    FileDownloader().downloaderForTesting
      ..processStatusUpdate(TaskStatusUpdate(_ourTask(), TaskStatus.complete))
      ..processStatusUpdate(TaskStatusUpdate(_hostTask(), TaskStatus.complete));
    await Future<void>.delayed(Duration.zero);

    expect(ours.map((u) => u.task.taskId), ['ours']);
    expect(
      host.map((u) => u.task.taskId),
      ['theirs'],
      reason: 'the host must receive its own task and only its own',
    );
  });

  test(
    'an external unregister does not leave a dead stream (#445 review)',
    () async {
      SmartDownloader.debugResolveUpdatesStream().listen((_) {}).cancel();

      // What `FileDownloader().destroy()` does to the callback map. It never
      // touches our controller — so "my controller is open" is NOT the same fact
      // as "I am still registered", and using it as one made every later download
      // hang with no error at all.
      FileDownloader().unregisterCallbacks(
        group: SmartDownloader.downloadGroup,
      );

      final got = <TaskUpdate>[];
      final sub = SmartDownloader.debugResolveUpdatesStream().listen(got.add);
      addTearDown(sub.cancel);
      FileDownloader().downloaderForTesting.processStatusUpdate(
        TaskStatusUpdate(_ourTask(), TaskStatus.running),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        got,
        hasLength(1),
        reason:
            'resolving again did not re-register, so the fan-out looked healthy '
            'and delivered nothing',
      );
    },
  );

  test('delivery still works after clearConfiguration', () async {
    SmartDownloader.debugResolveUpdatesStream().listen((_) {}).cancel();
    SmartDownloader.clearConfiguration();

    final got = <TaskUpdate>[];
    final sub = SmartDownloader.debugResolveUpdatesStream().listen(got.add);
    addTearDown(sub.cancel);
    FileDownloader().downloaderForTesting.processStatusUpdate(
      TaskStatusUpdate(_ourTask(), TaskStatus.running),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      got,
      hasLength(1),
      reason: 'a download after a reset must still work',
    );
  });

  test('priority: iOS gets the highest, Android must not be expedited', () {
    final packageDefault = DownloadTask(
      url: 'https://example.invalid/model.bin',
      filename: 'model.bin',
    ).priority;

    // Both arms asserted explicitly. flutter_test reports Android as the
    // default target platform, so relying on the ambient value would silently
    // test only one of the two.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      SmartDownloader.downloadPriority,
      0,
      reason:
          'iOS maps priority onto URLSession as 1 - p/10, so 10 gave 0.0 — '
          'below URLSessionTask.lowPriority — for a multi-gigabyte download',
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      SmartDownloader.downloadPriority,
      packageDefault,
      reason:
          'below the package default is expedited work on API 31+, and an '
          'expedited request cannot carry the 1s initial delay that '
          "background_downloader's 9-minute re-enqueue needs — the build "
          'throws, the throw is logged and swallowed, and the download stops '
          'at 9 minutes with no error at all',
    );
    expect(
      SmartDownloader.downloadPriority,
      isNot(lessThan(5)),
      reason: 'anything under 5 makes the Android job expedited',
    );
  });
}

DownloadTask _ourTask() => DownloadTask(
  taskId: 'ours',
  url: 'https://example.invalid/model.bin',
  filename: 'model.bin',
  group: SmartDownloader.downloadGroup,
  updates: Updates.statusAndProgress,
);

DownloadTask _hostTask() => DownloadTask(
  taskId: 'theirs',
  url: 'https://example.invalid/host.bin',
  filename: 'host.bin',
  updates: Updates.statusAndProgress,
);
