import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';

void main() {
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
