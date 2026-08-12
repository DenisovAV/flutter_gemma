// Pure-Dart verification of InflectTextFrontend against the espeak reference.
//
// The frontend reuses Matcha's word->IPA dictionary (word-level phonemes). Its
// output must match espeak's sentence phonemes EXACTLY except for
// context-dependent STRESS placement (espeak re-stresses function words by
// sentence position; a word dictionary can't — the same limitation Matcha
// ships with). So the gate is: phoneme content identical after stripping the
// primary/secondary stress marks (ˈ ˌ).
//
// Fixtures (test/inflect_fixtures/): Matcha's config.json (symbol table) +
// g2p_dict.txt.gz — Inflect reuses them (verified byte-identical symbol set).
import 'dart:io';

import 'package:flutter_gemma_speech/src/model/tts_model_profile.dart';
import 'package:flutter_gemma_speech/src/tts/inflect_text_frontend.dart';
import 'package:flutter_test/flutter_test.dart';

String _stripStress(String s) => s.replaceAll('ˈ', '').replaceAll('ˌ', '');

void main() {
  late InflectTextFrontend fe;
  late Map<int, String> idToSymbol;

  setUpAll(() async {
    final dir = '${Directory.current.path}/test/inflect_fixtures';
    fe = await InflectTextFrontend.load(const TtsModelProfile.inflect(), {
      'config.json': '$dir/config.json',
      'g2p_dict.txt.gz': '$dir/g2p_dict.txt.gz',
    });
    idToSymbol = {for (final e in fe.symbolToId.entries) e.value: e.key};
  });

  String phonemesOf(String text) =>
      fe.encode(text).map((id) => idToSymbol[id]).join();

  // (text, espeak reference phoneme string) — from the upstream espeak frontend.
  const cases = [
    ('Hello there, how are you today?', 'həlˈoʊ ðˈɛɹ, hˌaʊ ɑːɹ juː tədˈeɪ?'),
    ('Set a reminder for you.', 'sˈɛt ɐ ɹᵻmˈaɪndɚ fɔːɹ juː.'),
  ];

  for (final (text, espeak) in cases) {
    test('frontend phonemes match espeak (modulo stress): "$text"', () {
      final got = phonemesOf(text);
      // ignore: avoid_print
      print('  text:   "$text"\n  got:    "$got"\n  espeak: "$espeak"');
      expect(
        _stripStress(got),
        _stripStress(espeak),
        reason: 'phoneme content differs beyond stress marks',
      );
    });
  }
}
