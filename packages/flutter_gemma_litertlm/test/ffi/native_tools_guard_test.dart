import 'package:flutter_gemma_litertlm/src/ffi/ffi_inference_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLinuxX64NativeToolsBlocked', () {
    test('blocks native tools on Linux x86_64', () {
      expect(
        isLinuxX64NativeToolsBlocked(isLinuxX64: true, nativeTools: true),
        isTrue,
      );
    });

    test('allows text-format tools on Linux x86_64', () {
      expect(
        isLinuxX64NativeToolsBlocked(isLinuxX64: true, nativeTools: false),
        isFalse,
      );
    });

    test('allows native tools on other platforms', () {
      expect(
        isLinuxX64NativeToolsBlocked(isLinuxX64: false, nativeTools: true),
        isFalse,
      );
    });
  });
}
