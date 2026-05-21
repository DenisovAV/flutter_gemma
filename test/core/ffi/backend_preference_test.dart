import 'package:flutter_gemma/core/ffi/backend_preference.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ffiBackendFallbackOrder', () {
    test('tries NPU, then GPU, then CPU for an NPU preference', () {
      expect(
        ffiBackendFallbackOrder(PreferredBackend.npu),
        const [
          PreferredBackend.npu,
          PreferredBackend.gpu,
          PreferredBackend.cpu,
        ],
      );
    });

    test('tries GPU, then CPU for a GPU preference', () {
      expect(
        ffiBackendFallbackOrder(PreferredBackend.gpu),
        const [PreferredBackend.gpu, PreferredBackend.cpu],
      );
    });

    test('tries GPU, then CPU when no preference is provided', () {
      expect(
        ffiBackendFallbackOrder(null),
        const [PreferredBackend.gpu, PreferredBackend.cpu],
      );
    });

    test('tries only CPU for a CPU preference', () {
      expect(
        ffiBackendFallbackOrder(PreferredBackend.cpu),
        const [PreferredBackend.cpu],
      );
    });
  });

  group('ffiBackendWireName', () {
    test('serializes backend preferences for LiteRT-LM', () {
      expect(ffiBackendWireName(PreferredBackend.npu), 'npu');
      expect(ffiBackendWireName(PreferredBackend.gpu), 'gpu');
      expect(ffiBackendWireName(PreferredBackend.cpu), 'cpu');
    });
  });
}
