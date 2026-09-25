import 'dart:io';

import '../memory_snapshot.dart';

/// `Key:   1234 kB`: the shape of every size line in `smaps_rollup` and
/// `meminfo`. Lines without a `kB` unit (the rollup header, `HugePages_Total`)
/// do not match and are skipped.
final RegExp _kbLine = RegExp(r'^([A-Za-z0-9_()]+):\s+(\d+) kB$');

/// Parses every `Key: N kB` line of a `/proc` memory file into bytes.
Map<String, int> parseProcKbFields(String text) {
  final fields = <String, int>{};
  for (final line in text.split('\n')) {
    final match = _kbLine.firstMatch(line.trim());
    if (match == null) continue;
    fields[match.group(1)!] = int.parse(match.group(2)!) * 1024;
  }
  return fields;
}

/// `Private_Dirty + SwapPss` from the text of `/proc/self/smaps_rollup`.
///
/// Null unless both fields are present. Summing whatever happens to be there
/// would report a plausible number that means something else.
int? anonymousBytesFromSmapsRollup(String text) {
  final fields = parseProcKbFields(text);
  final privateDirty = fields['Private_Dirty'];
  final swapPss = fields['SwapPss'];
  if (privateDirty == null || swapPss == null) return null;
  return privateDirty + swapPss;
}

/// `MemAvailable` from the text of `/proc/meminfo`, or null if absent.
int? availableBytesFromMeminfo(String text) =>
    parseProcKbFields(text)['MemAvailable'];

/// Reads both values from `/proc`.
///
/// An unreadable file yields a null field rather than an error, because a
/// missing file means an older kernel, which is a documented null. The paths
/// are parameters only so tests can point at fixtures.
MemorySnapshot readProcMemorySnapshot({
  String smapsRollupPath = '/proc/self/smaps_rollup',
  String meminfoPath = '/proc/meminfo',
}) {
  return MemorySnapshot(
    anonymousBytes: _readOrNull(smapsRollupPath, anonymousBytesFromSmapsRollup),
    availableBytes: _readOrNull(meminfoPath, availableBytesFromMeminfo),
    takenAt: DateTime.now(),
  );
}

int? _readOrNull(String path, int? Function(String) parse) {
  final String text;
  try {
    text = File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  }
  return parse(text);
}
