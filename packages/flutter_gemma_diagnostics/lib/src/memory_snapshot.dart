import 'package:meta/meta.dart';

/// One reading of this process's memory, taken from the OS rather than from
/// any inference engine.
///
/// Every field is nullable, and each one documents why it can be null on a
/// given platform. A null means "the OS did not give us a number we can
/// defend", never zero.
@immutable
class MemorySnapshot {
  /// Creates a snapshot. Apps get one from `FlutterGemmaDiagnostics`.
  const MemorySnapshot({
    required this.anonymousBytes,
    required this.availableBytes,
    required this.takenAt,
  });

  /// Memory the OS charges to this process and cannot reclaim by dropping
  /// file pages. This is the number that decides whether the app is killed.
  ///
  /// Weights read from an mmapped model file are clean file pages and are not
  /// counted here. The same weights copied into the heap or a GPU-shared
  /// allocation are.
  ///
  /// - **iOS:** `phys_footprint` from `task_info(TASK_VM_INFO)`, the value
  ///   jetsam enforces its limit against.
  /// - **Android:** `Private_Dirty + SwapPss` from `/proc/self/smaps_rollup`.
  ///   `SwapPss` counts pages moved to zRAM, which still belong to the app.
  ///
  /// Null when:
  /// - on Android, `/proc/self/smaps_rollup` is missing (kernels older than
  ///   4.14) or does not report both fields;
  /// - on iOS, the kernel returns a `task_vm_info` too old to contain
  ///   `phys_footprint`.
  final int? anonymousBytes;

  /// Memory still available before the OS starts reclaiming or killing.
  ///
  /// The two platforms answer different questions, because they enforce
  /// memory differently:
  ///
  /// - **iOS:** `os_proc_available_memory()`, the headroom left before *this
  ///   app* reaches its jetsam limit. A per-app number.
  /// - **Android:** `MemAvailable` from `/proc/meminfo`, the kernel's estimate
  ///   of memory available to start new work *on the whole device*. Android
  ///   has no per-app hard limit; lmkd reacts to device-wide pressure.
  ///
  /// Null when:
  /// - on iOS, the call returns 0 or the OS predates iOS 13. Apple returns 0
  ///   both when no limit applies (the simulator) and when the limit is
  ///   already exceeded, and the two cannot be told apart;
  /// - on Android, `/proc/meminfo` has no `MemAvailable` line (kernels older
  ///   than 3.14).
  final int? availableBytes;

  /// When this snapshot was taken.
  final DateTime takenAt;

  @override
  bool operator ==(Object other) =>
      other is MemorySnapshot &&
      other.anonymousBytes == anonymousBytes &&
      other.availableBytes == availableBytes &&
      other.takenAt == takenAt;

  @override
  int get hashCode => Object.hash(anonymousBytes, availableBytes, takenAt);

  @override
  String toString() =>
      'MemorySnapshot(anonymousBytes: $anonymousBytes, '
      'availableBytes: $availableBytes, takenAt: $takenAt)';
}
