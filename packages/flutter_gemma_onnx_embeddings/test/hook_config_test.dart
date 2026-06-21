import 'package:flutter_gemma_onnx_embeddings/src/ort_hook_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kOnnxOrtNamespace', () {
    test('equals onnx_ort', () {
      expect(kOnnxOrtNamespace, equals('onnx_ort'));
    });
  });

  group('kOnnxOrtMainLibName', () {
    test('equals onnxruntime', () {
      expect(kOnnxOrtMainLibName, equals('onnxruntime'));
    });
  });

  group('kOnnxOrtChecksums', () {
    test('contains linux_x86_64 entry', () {
      expect(
        kOnnxOrtChecksums.keys,
        anyElement(contains('linux-x64')),
        reason: 'Linux x64 tarball must have a checksum entry',
      );
    });

    test('contains linux_arm64 entry', () {
      expect(
        kOnnxOrtChecksums.keys,
        anyElement(contains('linux-aarch64')),
        reason: 'Linux arm64 tarball must have a checksum entry',
      );
    });

    test('contains macos_arm64 entry', () {
      expect(
        kOnnxOrtChecksums.keys,
        anyElement(contains('osx-arm64')),
        reason: 'macOS arm64 tarball must have a checksum entry',
      );
    });

    test('contains windows_x86_64 entry', () {
      expect(
        kOnnxOrtChecksums.keys,
        anyElement(contains('win-x64')),
        reason: 'Windows x64 zip must have a checksum entry',
      );
    });

    test('contains android_arm64 entry', () {
      expect(
        kOnnxOrtChecksums.keys,
        anyElement(contains('android')),
        reason: 'Android AAR must have a checksum entry',
      );
    });

    test('no checksum value is an unfilled placeholder', () {
      final allEntries = kOnnxOrtChecksums.entries
          .where((e) => !e.key.contains('pod'))
          .toList();

      for (final entry in allEntries) {
        expect(
          entry.value,
          isNot(contains('<')),
          reason:
              '${entry.key} checksum must be a real SHA256, not a placeholder',
        );
        expect(
          entry.value,
          isNot(contains('>')),
          reason:
              '${entry.key} checksum must be a real SHA256, not a placeholder',
        );
        // SHA256 hex strings are exactly 64 characters.
        expect(
          entry.value.length,
          equals(64),
          reason: '${entry.key} checksum must be a 64-char hex SHA256',
        );
      }
    });

    test('android arm64 SHA256 matches known value', () {
      const expected =
          '09c0780ae8d734ef2774bdf498b624729a855e6f9a8e488a0e7398a4e7396032';
      final key = kOnnxOrtChecksums.keys.firstWhere(
        (k) => k.contains('android'),
      );
      expect(kOnnxOrtChecksums[key], equals(expected));
    });

    test('linux x64 SHA256 matches known value', () {
      const expected =
          '547e40a48f1fe73e3f812d7c88a948612c23f896b91e4e2ee1e232d7b468246f';
      final key = kOnnxOrtChecksums.keys.firstWhere(
        (k) => k.contains('linux-x64'),
      );
      expect(kOnnxOrtChecksums[key], equals(expected));
    });

    test('linux arm64 SHA256 matches known value', () {
      const expected =
          '3e4d83ac06924a32a07b6d7f91ce6f852876153fc0bbdf931bf517a140bfbe48';
      final key = kOnnxOrtChecksums.keys.firstWhere(
        (k) => k.contains('linux-aarch64'),
      );
      expect(kOnnxOrtChecksums[key], equals(expected));
    });

    test('macOS arm64 SHA256 matches known value', () {
      const expected =
          '545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a';
      final key = kOnnxOrtChecksums.keys.firstWhere(
        (k) => k.contains('osx-arm64'),
      );
      expect(kOnnxOrtChecksums[key], equals(expected));
    });

    test('windows x64 SHA256 matches known value', () {
      const expected =
          '6ebe99b5564bf4d029b6e93eac9ff423682b6212eade769e9ca3f685eaf500b4';
      final key = kOnnxOrtChecksums.keys.firstWhere(
        (k) => k.contains('win-x64'),
      );
      expect(kOnnxOrtChecksums[key], equals(expected));
    });

    test('windows arm64 SHA256 matches known value', () {
      const expected =
          'a32f2650575b3c20df462e337519fd1cc4105356130d11dba9771c6f374d952f';
      final key = kOnnxOrtChecksums.keys.firstWhere(
        (k) => k.contains('win-arm64'),
      );
      expect(kOnnxOrtChecksums[key], equals(expected));
    });
  });
}
