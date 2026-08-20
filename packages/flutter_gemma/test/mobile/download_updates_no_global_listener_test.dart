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
// The load-bearing assertion here is the first test. The rest cover lifecycle,
// and are honest about testing our own state rather than the package's.
import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
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

  test('priority is above the package default, not below it (#445)', () {
    final packageDefault = DownloadTask(
      url: 'https://example.invalid/model.bin',
      filename: 'model.bin',
    ).priority;

    expect(
      SmartDownloader.downloadPriority,
      lessThan(packageDefault),
      reason:
          'background_downloader documents 0 <= priority <= 10 with 0 the '
          'HIGHEST. This was 10 — worse than the package default of '
          '$packageDefault — so a multi-gigabyte download the user is actively '
          'waiting on was scheduled behind everything else',
    );
    expect(SmartDownloader.downloadPriority, 0);
  });
}
