// #447, half one: the POISONED order, and why it cannot be repaired.
//
// Hypothesis (now measured, see loader_order_fixed_447_test.dart for the other
// half): whichever code path first opens libLiteRtLm decides, for the whole
// process, whether stream_proxy.c's ABI probe can see the library's exports.
//
//   * the LLM path opens it via stream_proxy_load_global -> RTLD_GLOBAL
//   * the embeddings/speech path opens it via DynamicLibrary.open, and Dart
//     passes only RTLD_LAZY, which is RTLD_LOCAL by POSIX default
//   * bionic's dlsym(RTLD_DEFAULT) walks only soinfos flagged RTLD_GLOBAL
//   * so an app that touches embeddings before generating leaves the probe
//     blind: litert_lm_stream_chunk_get_text resolves to NULL, that is read as
//     "pre-v0.15 library", the 4-arg callback is registered against a 2-arg
//     caller, and args 3 and 4 are whatever x2/x3 happen to hold
//
// MUST run on Android, and MUST run as its own process. On Apple dlopen is
// RTLD_GLOBAL by default and dlsym(RTLD_DEFAULT) searches every loaded image,
// so this file cannot fail there — which is exactly how #447 shipped: the
// dual-ABI work was verified on macOS, the one platform where the property is
// unfalsifiable.
//
//   flutter test integration_test/loader_order_447_test.dart -d <android>
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'loader_order_447_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('poisoned order: a plain DynamicLibrary.open hides the ABI symbols', () {
    if (!Platform.isAndroid) {
      fail('Android only — this property is unfalsifiable on Apple');
    }

    // Baseline. If this is already true, something loaded the library before
    // us and the test has no signal — say so rather than reporting a pass on a
    // process that was never in the state under test.
    expect(
      globallyVisible(controlSymbol),
      isFalse,
      reason:
          'libLiteRtLm was already globally visible before this test opened '
          'anything; the process is not in a clean state, so neither result '
          'below means anything',
    );

    // What the embeddings/speech path does: litert_bindings.dart's
    // _openLiteRt() -> DynamicLibrary.open('libLiteRtLm.so').
    final lib = DynamicLibrary.open('libLiteRtLm.so');

    // Sanity: the library really is loaded and really does export both
    // symbols. Handle-scoped lookup ignores RTLD_GLOBAL entirely, so this
    // succeeds even when the ambient lookup below fails. If THIS fails, the
    // bundled library predates v0.15 and the hypothesis is moot.
    expect(
      lib.providesSymbol(probeSymbol),
      isTrue,
      reason:
          'bundled libLiteRtLm does not export the v0.15 chunk accessors — '
          'different problem entirely',
    );
    expect(lib.providesSymbol(controlSymbol), isTrue);

    // THE ASSERTION. The symbols exist, are exported, and the probe still
    // cannot see them.
    expect(
      globallyVisible(probeSymbol),
      isFalse,
      reason:
          'dlsym(RTLD_DEFAULT) CAN see the accessors after an RTLD_LOCAL open. '
          'Then bionic promoted the flags, or Dart no longer opens with '
          'RTLD_LAZY alone — either way the #447 explanation is wrong and the '
          'fix rests on a false premise',
    );
    expect(globallyVisible(controlSymbol), isFalse);
  });

  test('the poisoning cannot be repaired by loading globally afterwards', () {
    if (!Platform.isAndroid) {
      fail('Android only — this property is unfalsifiable on Apple');
    }

    // Runs second on purpose: it needs the poisoned process the test above
    // leaves behind. Do not reorder, and do not merge this file with
    // loader_order_fixed_447_test.dart — that one needs a CLEAN process, and
    // the two states cannot coexist in one.
    expect(
      globallyVisible(controlSymbol),
      isFalse,
      reason: 'expected the previous test to have left the library local',
    );

    // This is what the LLM path already does today. It is why #447 is subtle:
    // the call SUCCEEDS. bionic returns the existing soinfo with its refcount
    // bumped and its original flags intact — re-dlopen does not promote.
    // glibc does promote, which is why Linux never showed this.
    final handle = loadGlobal('libLiteRtLm.so');
    expect(
      handle,
      isNot(nullptr),
      reason:
          'stream_proxy_load_global returned NULL — then the existing null '
          'check would already have caught this and #447 would have been a '
          'loud failure instead of a silent one',
    );

    expect(
      globallyVisible(probeSymbol),
      isFalse,
      reason:
          'a later RTLD_GLOBAL dlopen DID promote the soinfo. Then the fix '
          'could simply be "always call loadGlobal before probing" — much '
          'cheaper than making every load path global',
    );
  });
}
