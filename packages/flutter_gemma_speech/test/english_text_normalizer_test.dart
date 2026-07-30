import 'package:flutter_gemma_speech/src/tts/english_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final n = EnglishTextNormalizer({' ', '.', ',', '?'}); // subset for the test
  test('Hello world. -> [Word(hello) Sym( ) Word(world) Sym(.)]', () {
    final t = n.normalize('Hello world.');
    expect(
      t
          .map(
            (x) => x is WordToken
                ? 'W:${x.word}'
                : 'S:${(x as SymbolToken).symbol}',
          )
          .toList(),
      ['W:hello', 'S: ', 'W:world', 'S:.'],
    );
  });
  test('comma becomes a SymbolToken, not stripped', () {
    final t = n.normalize('Sure, ok');
    expect(t.whereType<SymbolToken>().map((s) => s.symbol), contains(','));
  });
  test('splitClauses splits on sentence + clause boundaries', () {
    expect(n.splitClauses('One, two. Three'), ['One,', 'two.', 'Three']);
  });
}
