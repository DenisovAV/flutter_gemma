import 'dart:typed_data';

import 'package:flutter_gemma_speech/src/tts/matcha_text_frontend.dart';
import 'package:flutter_gemma_speech/src/tts/tts_frontend_input.dart';
import 'package:flutter_gemma_speech/src/tts/tts_text_frontend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tiny table WITH a space symbol (unlike the fixture in
  // tts_text_frontend_test.dart) so a multi-word chunk round-trips through
  // the normalizer's SymbolToken(' ') without hitting the fail-loud
  // unmapped-symbol throw.
  MatchaTextFrontend fe({NeuralG2pResolver? g2p}) => MatchaTextFrontend(
    symbolToId: {'_': 0, ' ': 1, '.': 2, 'a': 3, 'b': 4},
    dictionary: {'ab': 'ab'},
    embeddingTable: Float32List(5 * 2),
    nChannels: 2,
    maxText: 16,
    neuralG2p: g2p,
  );

  test('known word + trailing period recompose (symbols kept)', () {
    // normalize('ab.') -> [WordToken(ab), SymbolToken(.)] -> dict['ab']
    // + '.' recomposed as "ab." -> IPA runes [a,b,.] -> pids [3,4,2] ->
    // realLen = 2*3 + 1 = 7.
    final o = fe().encode('ab.');
    expect(o, isA<MatchaFrontendInput>());
    expect(o.realLen, 7);
  });

  test('OOV word routes through neural resolver', () {
    var called = '';
    final o = fe(
      g2p: (w) {
        called = w;
        return 'ab';
      },
    ).encode('zz');
    expect(called, 'zz');
    expect(o.realLen, greaterThan(0));
  });

  test('OOV word with no resolver throws', () {
    expect(() => fe().encode('zz'), throwsA(isA<StateError>()));
  });

  test(
    'non-speech chunk (no symbols mapped) returns empty input, not a throw',
    () {
      // '👍' is not a letter, not whitespace, and not in the tiny symbol
      // table, so the normalizer drops it entirely -> zero tokens -> zero
      // pids. encode() must return a defined empty MatchaFrontendInput
      // (realLen 0) instead of throwing, so the worker's `realLen <= 1`
      // guard can skip this clause without erroring the whole request.
      final o = fe().encode('👍');
      expect(o, isA<MatchaFrontendInput>());
      expect(o.realLen, 0);
      expect(o.symbolEmbeddings, isEmpty);
      expect(o.textMask, isEmpty);
    },
  );
}
