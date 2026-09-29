import 'package:flutter_gemma_litertlm/src/ffi/ffi_inference_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLinuxNativeToolsBlocked', () {
    test('blocks native tools on Linux x86_64', () {
      expect(
        isLinuxNativeToolsBlocked(isLinux: true, nativeTools: true),
        isTrue,
      );
    });

    test('blocks native tools on Linux arm64', () {
      expect(
        isLinuxNativeToolsBlocked(isLinux: true, nativeTools: true),
        isTrue,
      );
    });

    test('allows text-format tools on Linux', () {
      expect(
        isLinuxNativeToolsBlocked(isLinux: true, nativeTools: false),
        isFalse,
      );
    });

    test('allows native tools on other platforms', () {
      expect(
        isLinuxNativeToolsBlocked(isLinux: false, nativeTools: true),
        isFalse,
      );
    });
  });
}
