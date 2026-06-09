import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for issue #314 — the model manager set
/// `_isInitialized = true` synchronously BEFORE awaiting the async restore,
/// so a concurrent second `initialize()` returned before the first finished
/// restoring the active model, and `getActiveModel()` then saw a null active
/// spec and threw StateError.
/// https://github.com/DenisovAV/flutter_gemma/issues/314
///
/// Distilled Buggy/Fixed pair (mirrors model_creation_failure_test.dart):
/// `_restore()` is an async step that sets `active` only after an await; the
/// guard must not report "initialized" until that completes.

/// Buggy guard: flag flipped before the async restore — concurrent callers
/// skip the in-flight restore.
class BuggyManager {
  bool _isInitialized = false;
  String? active;
  int restoreCount = 0;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true; // BUG: set before await
    await _restore();
  }

  Future<void> _restore() async {
    restoreCount++;
    await Future<void>.delayed(Duration.zero); // simulate async prefs read
    active = 'model-a';
  }
}

/// Fixed guard: cached future — concurrent callers share the one init and all
/// await the same completed restore.
class FixedManager {
  Future<void>? _initFuture;
  String? active;
  int restoreCount = 0;

  Future<void> initialize() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await _restore();
  }

  Future<void> _restore() async {
    restoreCount++;
    await Future<void>.delayed(Duration.zero);
    active = 'model-a';
  }
}

void main() {
  group('Issue #314 — init race (bug)', () {
    test('BUG: concurrent initialize() lets a caller proceed before restore',
        () async {
      final m = BuggyManager();
      final first = m.initialize();
      await m.initialize();
      expect(m.active, isNull,
          reason: 'BUG: 2nd caller returned before restore set active');
      await first;
      expect(m.active, 'model-a');
    });
  });

  group('Issue #314 — init race (fix)', () {
    test('FIX: concurrent initialize() all await one completed restore',
        () async {
      final m = FixedManager();
      await Future.wait([m.initialize(), m.initialize(), m.initialize()]);
      expect(m.active, 'model-a',
          reason: 'FIX: every caller observes the completed restore');
      expect(m.restoreCount, 1,
          reason: 'FIX: single-flight — restore runs exactly once');
    });

    test('FIX: a later initialize() after completion is a no-op', () async {
      final m = FixedManager();
      await m.initialize();
      await m.initialize();
      expect(m.restoreCount, 1);
    });
  });
}
