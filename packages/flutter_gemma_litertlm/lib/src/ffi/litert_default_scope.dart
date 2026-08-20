// Putting libLiteRtLm into the process-wide default symbol search scope, and
// proving that it landed there.
//
// WHY THIS EXISTS (#447)
//
// On Android, the FIRST dlopen of a library decides whether its exports are
// reachable through `dlsym(RTLD_DEFAULT)`, and nothing afterwards can change
// that decision:
//
//   * Dart's `DynamicLibrary.open` passes RTLD_LAZY only, which is RTLD_LOCAL
//     by POSIX default, so the soinfo is filed WITHOUT the RTLD_GLOBAL flag
//   * bionic's `dlsym(RTLD_DEFAULT)` walks only soinfos carrying that flag
//   * re-opening the same file with RTLD_GLOBAL returns the EXISTING soinfo
//     with its refcount bumped and its flags untouched — bionic does not
//     promote (glibc does, which is why Linux never showed this)
//
// So an app that reaches embeddings or speech before generating leaves
// stream_proxy.c's ABI probe blind: `litert_lm_stream_chunk_get_text` resolves
// to NULL, that is read as "pre-v0.15 library", and the 4-arg callback shape
// is registered against a 2-arg caller. Arguments 3 and 4 are then whatever
// x2/x3 happen to hold, and `strdup` runs on the result.
//
// Measured on an API 36 arm64 emulator (`loader_order_447_test.dart` and
// `loader_order_fixed_447_test.dart` in the example's integration tests):
//
//   plain open first                      -> not visible
//   plain open, then RTLD_GLOBAL open     -> STILL not visible, handle non-NULL
//   RTLD_GLOBAL open, then plain open     -> visible
//
// The middle row is why this file verifies rather than trusts. The last row is
// why preventing the bad order is sufficient: a later RTLD_LOCAL open does not
// demote an already-global soinfo, so exactly one call site had to change.
//
// ANDROID ONLY, deliberately. On glibc a later RTLD_GLOBAL dlopen promotes the
// object, so Linux repairs itself as soon as the LLM path runs. Windows has no
// local/global distinction for PE modules — exports are reachable through the
// loaded-module list either way, which is why stream_proxy_resolve uses
// GetModuleHandleA there instead of a default-scope lookup. And on Apple
// dlopen defaults to RTLD_GLOBAL, so `dlsym(RTLD_DEFAULT)` searches every
// loaded image. Applying this to those platforms would mean picking a control
// symbol out of a different library for no behavioural gain.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Exported by EVERY version of libLiteRtLm, which is what makes it usable as
/// a control: its ambient visibility answers "is this library in the default
/// search scope", separately from "does this library have the v0.15 chunk
/// accessors". Probing an accessor directly could not tell those apart — and
/// collapsing them is the whole of #447.
const _controlSymbol = 'litert_lm_engine_create';

typedef _LoadGlobalNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _LoadGlobalDart = Pointer<Void> Function(Pointer<Utf8>);

/// Loads [soname] with `RTLD_LAZY | RTLD_GLOBAL` and confirms its exports are
/// reachable from the default search scope.
///
/// Call this BEFORE any `DynamicLibrary.open` of the same library, from every
/// path that might be the first to touch it. It is safe to call repeatedly and
/// from any isolate: the underlying dlopen is idempotent, and isolates share
/// one process and therefore one loader state.
///
/// Throws with a distinguishable message for each of the two failures, because
/// they need different fixes:
///   * the library could not be loaded at all (usually API < 30, see #265)
///   * the library loaded but is not in the default scope, meaning something
///     opened it locally first (#447)
void ensureLiteRtLmInDefaultScope(String soname) {
  final proxy = DynamicLibrary.open('libStreamProxy.so');
  final loadGlobal = proxy.lookupFunction<_LoadGlobalNative, _LoadGlobalDart>(
    'stream_proxy_load_global',
  );

  final pathPtr = soname.toNativeUtf8();
  final Pointer<Void> handle;
  try {
    handle = loadGlobal(pathPtr);
  } finally {
    calloc.free(pathPtr);
  }

  if (handle == nullptr) {
    // The most common cause we've seen is Android API < 30 (#265): upstream
    // `libLiteRtLm.so` is built against Bionic 11+ libc and hard-references
    // `pthread_cond_clockwait` / `sem_clockwait`, which do not exist on API 29
    // and below.
    throw Exception(
      'Failed to load $soname with RTLD_GLOBAL. On Android this commonly '
      'indicates API < 30: `.litertlm` models require Android 11+ '
      '(minSdkVersion 30). For older devices use a MediaPipe `.task` model '
      'instead. See https://github.com/DenisovAV/flutter_gemma/issues/265',
    );
  }

  // A non-NULL handle does NOT mean the call did what it was asked to do. If
  // the library was already open, bionic returned the existing soinfo with its
  // original flags, and the load "succeeded" while changing nothing. That is
  // precisely the state #447 shipped in, and only this check can see it.
  if (DynamicLibrary.process().providesSymbol(_controlSymbol)) return;

  throw StateError(
    '$soname is loaded but its symbols are not in the default search scope. '
    'Something opened it with a plain DynamicLibrary.open before this call, '
    'and bionic does not promote an already-loaded library to RTLD_GLOBAL, so '
    'the condition is permanent for this process. Continuing would register '
    'the wrong stream-callback ABI and corrupt generated text. Route every '
    'load of $soname through ensureLiteRtLmInDefaultScope. '
    'See https://github.com/DenisovAV/flutter_gemma/issues/447',
  );
}
