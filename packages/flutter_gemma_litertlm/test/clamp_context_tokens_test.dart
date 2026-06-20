// Regression test for #318: a maxTokens below the model's baked
// `kv_cache_max_len` (1024 for every supported .litertlm model) underflows the
// native KV-cache resize and DYNAMIC_UPDATE_SLICE crashes at generation.
// `clampLitertlmContextTokens` raises any value below the floor up to it.
//
// Reproduced on Pixel 8a (Gemma 4 E2B, CPU): 100/256/512 crash, 1024/4096 work.
@TestOn('vm')
library;

import 'package:flutter_gemma_litertlm/src/litert_lm_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clampLitertlmContextTokens (#318)', () {
    test('the floor constant is 1024 (the max known kv_cache_max_len)', () {
      expect(kMinLitertlmContextTokens, 1024);
    });

    test('clamps values below the floor up to 1024', () {
      // The user's exact value, plus the verified-crashing thresholds.
      expect(clampLitertlmContextTokens(100), 1024);
      expect(clampLitertlmContextTokens(256), 1024);
      expect(clampLitertlmContextTokens(512), 1024);
      expect(clampLitertlmContextTokens(1), 1024);
      expect(clampLitertlmContextTokens(1023), 1024);
    });

    test('leaves the floor itself untouched', () {
      expect(clampLitertlmContextTokens(1024), 1024);
    });

    test('passes through values above the floor unchanged', () {
      expect(clampLitertlmContextTokens(2048), 2048);
      expect(clampLitertlmContextTokens(4096), 4096);
      expect(clampLitertlmContextTokens(8192), 8192);
    });

    test('handles zero (treated as below the floor)', () {
      expect(clampLitertlmContextTokens(0), 1024);
    });
  });
}
