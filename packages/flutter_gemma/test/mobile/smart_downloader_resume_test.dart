import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';

void main() {
  group('shouldConfigureForegroundNotification (#356)', () {
    test('foreground: true requires a notification', () {
      expect(shouldConfigureForegroundNotification(true), isTrue);
    });

    test('foreground: null (auto-detect) requires a notification — a large '
        'file can still trigger foreground at runtime', () {
      expect(shouldConfigureForegroundNotification(null), isTrue);
    });

    test('foreground: false does not need a notification', () {
      expect(shouldConfigureForegroundNotification(false), isFalse);
    });
  });

  group('decideFailedDownloadAction', () {
    test('resumes while under the resume-attempt cap', () {
      expect(
        decideFailedDownloadAction(
          canResume: true,
          resumeAttempt: 0,
          currentAttempt: 0,
          maxRetries: 10,
          maxResumeAttempts: kMaxResumeAttempts,
        ),
        ResumeAction.resume,
      );
    });

    test(
      'stops resuming and falls through to retry once resume cap is hit',
      () {
        expect(
          decideFailedDownloadAction(
            canResume: true,
            resumeAttempt: kMaxResumeAttempts,
            currentAttempt: 1,
            maxRetries: 10,
            maxResumeAttempts: kMaxResumeAttempts,
          ),
          ResumeAction.retry,
        );
      },
    );

    test('retries when resume not possible but retries remain', () {
      expect(
        decideFailedDownloadAction(
          canResume: false,
          resumeAttempt: 0,
          currentAttempt: 2,
          maxRetries: 10,
          maxResumeAttempts: kMaxResumeAttempts,
        ),
        ResumeAction.retry,
      );
    });

    test('gives up when resume cap AND retry cap are both exhausted', () {
      expect(
        decideFailedDownloadAction(
          canResume: true,
          resumeAttempt: kMaxResumeAttempts,
          currentAttempt: 10,
          maxRetries: 10,
          maxResumeAttempts: kMaxResumeAttempts,
        ),
        ResumeAction.giveUp,
      );
    });
  });

  group('resume-attempt sequencing', () {
    test(
      'three consecutive resumable failures then a retry (the #355 sequence)',
      () {
        // Simulate the loop's decisions with an incrementing resumeAttempt.
        final actions = <ResumeAction>[];
        var resumeAttempt = 0;
        for (var i = 0; i < 4; i++) {
          final a = decideFailedDownloadAction(
            canResume: true,
            resumeAttempt: resumeAttempt,
            currentAttempt: 0,
            maxRetries: 10,
            maxResumeAttempts: kMaxResumeAttempts,
          );
          actions.add(a);
          if (a == ResumeAction.resume) resumeAttempt++;
        }
        // 3 resumes (0,1,2), then the 4th (resumeAttempt==3) falls through to retry.
        expect(actions, [
          ResumeAction.resume,
          ResumeAction.resume,
          ResumeAction.resume,
          ResumeAction.retry,
        ]);
      },
    );
  });

  group('armResumeWatchdog', () {
    test('fires onTimeout after the watchdog duration when not cancelled', () {
      fakeAsync((async) {
        var fired = false;
        armResumeWatchdog(
          progress: StreamController<int>(),
          onTimeout: () => fired = true,
          timeout: const Duration(seconds: 90),
        );
        async.elapse(const Duration(seconds: 89));
        expect(fired, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(
          fired,
          isTrue,
        ); // hung task → watchdog fires → stream would close
      });
    });

    test(
      'does not fire if cancelled before the timeout (resume succeeded)',
      () {
        fakeAsync((async) {
          var fired = false;
          final t = armResumeWatchdog(
            progress: StreamController<int>(),
            onTimeout: () => fired = true,
            timeout: const Duration(seconds: 90),
          );
          async.elapse(const Duration(seconds: 30));
          t.cancel(); // a progress/complete event arrived → cancel the watchdog
          async.elapse(const Duration(seconds: 120));
          expect(fired, isFalse);
        });
      },
    );
  });

  group('resume-counter race window (#357 review, FIX 2)', () {
    // Reproduces the shape of the fix in _downloadWithSmartRetry's listener:
    // capture-and-increment `localResumeAttempt` SYNCHRONOUSLY before an
    // await, rather than after it resolves. This proves two "concurrent"
    // failed events (modeled here as two overlapping async decisions racing
    // against the same counter) see DIFFERENT resumeAttempt values, whereas
    // the old post-await-increment shape would let both read the same stale
    // value.
    Future<int> handleFailedDownloadStub({
      required bool resumeWillHappen,
      required Duration awaitDelay,
    }) async {
      // Simulates _handleFailedDownload's internal await (e.g. taskCanResume
      // + downloader.resume/backoff) without depending on the real plugin.
      await Future<void>.delayed(awaitDelay);
      return resumeWillHappen ? 1 : 0; // arbitrary "work done" marker
    }

    test(
      'two overlapping failed events see different resumeAttempt values',
      () async {
        var localResumeAttempt = 0;
        final seenAttempts = <int>[];

        Future<void> onFailedEvent(Duration awaitDelay) async {
          // FIX 2 shape: capture + increment BEFORE the await.
          final attemptForThisRound = localResumeAttempt;
          localResumeAttempt++;
          seenAttempts.add(attemptForThisRound);

          final resumePending =
              await handleFailedDownloadStub(
                resumeWillHappen: true,
                awaitDelay: awaitDelay,
              ) ==
              1;

          if (!resumePending) {
            localResumeAttempt--; // give the slot back
          }
        }

        // Fire two "failed" events back-to-back without awaiting the first
        // before starting the second — this is what a broadcast stream's
        // non-serialized onData handlers can do.
        final f1 = onFailedEvent(const Duration(milliseconds: 20));
        final f2 = onFailedEvent(const Duration(milliseconds: 5));
        await Future.wait([f1, f2]);

        // Both events must have captured DIFFERENT resumeAttempt values
        // (0 and 1, in dispatch order) even though f2's await resolved first.
        expect(seenAttempts, [0, 1]);
        expect(localResumeAttempt, 2); // both resumed → both consumed a slot
      },
    );

    test(
      'a non-resuming failure gives its slot back (does not consume budget)',
      () async {
        var localResumeAttempt = 0;

        final attemptForThisRound = localResumeAttempt;
        localResumeAttempt++;

        final resumePending =
            await handleFailedDownloadStub(
              resumeWillHappen: false,
              awaitDelay: const Duration(milliseconds: 1),
            ) ==
            1;

        if (!resumePending) {
          localResumeAttempt--;
        }

        expect(attemptForThisRound, 0);
        expect(resumePending, isFalse);
        // Slot given back — a subsequent real resume still starts at 0.
        expect(localResumeAttempt, 0);
      },
    );
  });

  group('watchdog completer settlement (#357 review, FIX 3)', () {
    test(
      'watchdog fire calls onSettle so a waiting completer is not leaked',
      () {
        fakeAsync((async) {
          final completer = Completer<void>();
          var cancellationListenerCancelled = false;
          // Mirrors downloadWithProgress's
          // `.whenComplete(() => cancellationListener?.cancel())`.
          completer.future.whenComplete(() {
            cancellationListenerCancelled = true;
          });

          // Mirrors _armResumeWatchdog composing onTimeout with onSettle.
          armResumeWatchdog(
            progress: StreamController<int>(),
            onTimeout: () {
              if (!completer.isCompleted) completer.complete();
            },
            timeout: const Duration(seconds: 90),
          );

          expect(cancellationListenerCancelled, isFalse);
          async.elapse(const Duration(seconds: 90));
          // Flush the completer's async .whenComplete callback.
          async.flushMicrotasks();

          expect(completer.isCompleted, isTrue);
          expect(cancellationListenerCancelled, isTrue);
        });
      },
    );

    test('onSettle guards against double-complete', () {
      fakeAsync((async) {
        final completer = Completer<void>();
        void onSettle() {
          if (!completer.isCompleted) completer.complete();
        }

        // Simulate the watchdog firing AND a terminal status update racing
        // in — both try to settle the same completer.
        onSettle();
        expect(() => onSettle(), returnsNormally);
        expect(completer.isCompleted, isTrue);
      });
    });
  });

  group('per-taskId watchdog isolation (concurrent downloads, #355 follow-up)', () {
    // SmartDownloader keys its real watchdogs by taskId in a
    // `Map<String, Timer>` (see `_resumeWatchdogs` in smart_downloader.dart) so
    // that two concurrent downloads never clobber each other's timer. That map
    // and its arm/cancel wrappers are private, so this test reconstructs the
    // exact same arm/cancel/fire-removes-entry shape with the public
    // `armResumeWatchdog` factory + a local map, to prove the pattern is sound
    // for concurrent taskIds without needing a fake-downloader harness.
    Timer arm(
      Map<String, Timer> watchdogs,
      String taskId,
      StreamController<int> progress,
      void Function() onTimeout,
    ) {
      watchdogs.remove(taskId)?.cancel();
      final timer = armResumeWatchdog(
        progress: progress,
        onTimeout: () {
          watchdogs.remove(taskId);
          onTimeout();
        },
      );
      watchdogs[taskId] = timer;
      return timer;
    }

    void cancel(Map<String, Timer> watchdogs, String taskId) {
      watchdogs.remove(taskId)?.cancel();
    }

    test('cancelling task A watchdog does not cancel task B watchdog', () {
      fakeAsync((async) {
        final watchdogs = <String, Timer>{};
        var firedA = false;
        var firedB = false;

        arm(watchdogs, 'taskA', StreamController<int>(), () => firedA = true);
        arm(watchdogs, 'taskB', StreamController<int>(), () => firedB = true);
        expect(watchdogs.keys, containsAll(<String>['taskA', 'taskB']));

        // A live progress event for task A cancels ONLY task A's watchdog.
        cancel(watchdogs, 'taskA');
        expect(watchdogs.containsKey('taskA'), isFalse);
        expect(watchdogs.containsKey('taskB'), isTrue);

        async.elapse(const Duration(seconds: 90));
        // Task A was genuinely fine (cancelled) — never fires.
        expect(firedA, isFalse);
        // Task B was never cancelled — it was silently dead, so it fires.
        expect(firedB, isTrue);
      });
    });

    test('re-arming task A does not touch task B\'s timer', () {
      fakeAsync((async) {
        final watchdogs = <String, Timer>{};
        var firedA = false;
        var firedB = false;

        arm(watchdogs, 'taskA', StreamController<int>(), () => firedA = true);
        arm(watchdogs, 'taskB', StreamController<int>(), () => firedB = true);

        async.elapse(const Duration(seconds: 30));
        // Task A fails again and re-arms its OWN watchdog (fresh 90s window).
        arm(watchdogs, 'taskA', StreamController<int>(), () => firedA = true);

        async.elapse(const Duration(seconds: 60));
        // Task B's original timer (armed at t=0) fires at t=90.
        expect(firedB, isTrue);
        // Task A's re-armed timer (armed at t=30) hasn't reached 90s yet.
        expect(firedA, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(firedA, isTrue);
      });
    });

    test('firing removes only that taskId\'s entry from the map (no leak)', () {
      fakeAsync((async) {
        final watchdogs = <String, Timer>{};
        arm(watchdogs, 'taskA', StreamController<int>(), () {});
        arm(watchdogs, 'taskB', StreamController<int>(), () {});

        async.elapse(const Duration(seconds: 90));
        // Both fired and self-removed — map must be empty, not leaking.
        expect(watchdogs, isEmpty);
      });
    });
  });
}
