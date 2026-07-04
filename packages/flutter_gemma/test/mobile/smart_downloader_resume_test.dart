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
}
