import 'dart:typed_data';

import 'package:flutter_gemma_diagnostics/src/ios/mach_memory.dart';
import 'package:flutter_test/flutter_test.dart';

/// A zeroed `task_vm_info_data_t` buffer with [physFootprint] written where
/// the kernel puts it.
ByteData _taskVmInfo({required int physFootprint, int lengthInBytes = 512}) {
  return ByteData(lengthInBytes)
    ..setUint64(physFootprintOffset, physFootprint, Endian.host);
}

void main() {
  group('task_vm_info layout', () {
    test('phys_footprint follows 17 eight-byte and 2 four-byte fields', () {
      expect(physFootprintOffset, 17 * 8 + 2 * 4);
    });

    test('the rev-1 count ends exactly after phys_footprint', () {
      expect(taskVmInfoRev1Count * 4, physFootprintOffset + 8);
    });
  });

  group('physFootprintFromTaskVmInfo', () {
    test('reads phys_footprint when the reply includes revision 1', () {
      const footprint = 1234567890123;
      final info = _taskVmInfo(physFootprint: footprint);
      expect(physFootprintFromTaskVmInfo(info, taskVmInfoRev1Count), footprint);
    });

    test('reads it from a newer, longer reply', () {
      final info = _taskVmInfo(physFootprint: 42);
      expect(physFootprintFromTaskVmInfo(info, 128), 42);
    });

    test('is null when the kernel wrote less than revision 1', () {
      final info = _taskVmInfo(physFootprint: 42);
      expect(
        physFootprintFromTaskVmInfo(info, taskVmInfoRev1Count - 1),
        isNull,
      );
    });

    test('is null when the buffer cannot hold the field', () {
      final info = ByteData(physFootprintOffset + 4);
      expect(physFootprintFromTaskVmInfo(info, 128), isNull);
    });
  });

  group('availableBytesFromOsProc', () {
    test('passes a real headroom through', () {
      expect(availableBytesFromOsProc(3 * 1024 * 1024 * 1024), 3 << 30);
    });

    test('maps 0 to null: no limit and limit exceeded look the same', () {
      expect(availableBytesFromOsProc(0), isNull);
    });
  });
}
