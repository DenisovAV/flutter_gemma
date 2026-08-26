// The committed Apple `vec0` loadables must declare minos 13.0.
//
// Flutter hardcodes `MinimumOSVersion 13.0` into the Native-Assets framework
// wrapper it generates, and App Store Connect compares each framework's BINARY
// against ITS OWN wrapper plist — so a slice declaring anything else is
// ITMS-90208 regardless of the app's deployment target.
//
// This repo has shipped that rejection twice: once as #286, and once here,
// where asg017's upstream tarball carried the legacy `LC_VERSION_MIN_IPHONEOS
// 7.0` and the simulator slice carried 14.0. Both times the only guard was a
// step inside a build script a human had to remember to run — and the second
// time that step was normalizing a tarball nobody consumes while the shipped
// bytes went unchecked.
//
// So this reads the FILES THAT SHIP, parses the Mach-O load commands itself
// rather than shelling out to `vtool`, and therefore runs on Linux CI too.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _lcVersionMinIphoneos = 0x25;
const _lcBuildVersion = 0x32;
// PLATFORM_* from mach-o/loader.h. IOS is 2 — 1 is MACOS, which is exactly
// the confusion a wrong `vtool` platform argument produces, so the numbers are
// spelled out rather than guessed.
const _platformIos = 2;
const _platformIosSimulator = 7;

/// (platform, minos) from the first version-declaring load command, or null.
({int platform, String minos})? _buildVersion(File f) {
  final b = ByteData.sublistView(f.readAsBytesSync());
  final magic = b.getUint32(0, Endian.little);
  if (magic != 0xfeedfacf) return null; // 64-bit little-endian Mach-O only
  final ncmds = b.getUint32(16, Endian.little);
  var off = 32; // mach_header_64
  for (var i = 0; i < ncmds; i++) {
    final cmd = b.getUint32(off, Endian.little);
    final size = b.getUint32(off + 4, Endian.little);
    if (cmd == _lcBuildVersion) {
      final platform = b.getUint32(off + 8, Endian.little);
      final v = b.getUint32(off + 12, Endian.little);
      return (platform: platform, minos: '${v >> 16}.${(v >> 8) & 0xff}');
    }
    if (cmd == _lcVersionMinIphoneos) {
      // The legacy command. Present at all means the slice was never
      // normalized — that is the state that shipped 7.0.
      final v = b.getUint32(off + 8, Endian.little);
      return (platform: -1, minos: '${v >> 16}.${(v >> 8) & 0xff}');
    }
    off += size;
  }
  return null;
}

void main() {
  final root = Directory('native/sqlite_vec/prebuilt');

  test('every committed iOS vec0 slice declares minos 13.0', () {
    expect(root.existsSync(), isTrue, reason: 'prebuilt dir moved');

    const expected = {
      'ios_arm64': _platformIos,
      'ios_sim_arm64': _platformIosSimulator,
    };

    for (final entry in expected.entries) {
      final lib = File('${root.path}/${entry.key}/libvec0.dylib');
      expect(lib.existsSync(), isTrue, reason: '${entry.key} is missing');

      final got = _buildVersion(lib);
      expect(got, isNotNull, reason: '${entry.key}: no version load command');
      expect(
        got!.minos,
        '13.0',
        reason:
            '${entry.key} declares minos ${got.minos}. Re-run '
            'native/sqlite_vec/build_local.sh (it normalizes on install), or '
            'vtool -set-build-version.',
      );
      expect(
        got.platform,
        entry.value,
        reason:
            '${entry.key} declares platform ${got.platform} — a wrong vtool '
            'platform argument is accepted silently and fails later at dlopen',
      );
    }
  });
}
