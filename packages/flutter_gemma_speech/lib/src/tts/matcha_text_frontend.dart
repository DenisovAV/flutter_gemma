/// Matcha-TTS text frontend — `text -> IPA (dictionary G2P) -> symbol ids ->
/// blank-interspersed ids + text mask -> host-side emb.bin gather -> symbol
/// embeddings`. Pure Dart, no FFI. The analog of STT's `HfTokenizer`: this is
/// the input `TtsCore` (Task 2.3) feeds to the Matcha text-encoder graph.
///
/// The algorithm is transcribed verbatim from the verified reconstruction
/// script `matcha_synth.dart` (`main()`, config/dict/emb parsing + G2P +
/// blank-intersperse + gather).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/tts_model_profile.dart';
import 'tts_frontend_input.dart';
import 'tts_text_frontend.dart';
import 'tts_text_normalizer.dart';

/// Pure-Dart Matcha-TTS text frontend: text normalizer (tagged tokens) +
/// dictionary G2P + optional neural fallback + blank-intersperse +
/// host-side embedding gather. OOV words throw when no neural resolver is
/// wired.
class MatchaTextFrontend implements TtsTextFrontend {
  /// Pure constructor from already-parsed data (unit-testable, no file I/O).
  MatchaTextFrontend({
    required this.symbolToId,
    required this.dictionary,
    required this.embeddingTable,
    required this.nChannels,
    required this.maxText,
    this.locale = 'en_us',
    this.neuralG2p,
  });

  /// IPA char -> symbol id (178-symbol table for the real Matcha bundle).
  final Map<String, int> symbolToId;

  /// Lowercase word -> IPA string (274,927 entries for the real bundle).
  final Map<String, String> dictionary;

  /// [nSymbols * nChannels] row-major phoneme embedding table.
  final Float32List embeddingTable;

  /// Embedding width (192 for the real Matcha bundle).
  final int nChannels;

  /// Max text length in symbol slots (256 for the real Matcha bundle).
  final int maxText;

  /// Selects the normalizer for this frontend (Task 9); matcha -> `'en_us'`.
  final String locale;

  /// Neural G2P fallback for OOV words (Task 11 wires this in via the
  /// worker); null until then, so OOV words still throw.
  final NeuralG2pResolver? neuralG2p;

  /// Parse the real Matcha bundle files: `config.json` (symbols +
  /// n_channels + MAX_TEXT), `g2p_dict.txt.gz` (gzipped word -> IPA
  /// dictionary), `emb.bin` (little-endian f32 phoneme embedding table).
  static Future<MatchaTextFrontend> load(
    TtsModelProfile profile,
    Map<String, String> paths, {
    NeuralG2pResolver? neuralG2p,
  }) async {
    final configPath = paths[profile.configFile]!;
    final dictPath = paths[profile.dictFile]!;
    final embeddingPath = paths[profile.embeddingFile]!;

    final config =
        jsonDecode(await File(configPath).readAsString())
            as Map<String, dynamic>;
    final symbols = (config['symbols'] as List).cast<String>();
    final symbolToId = <String, int>{
      // last-wins on duplicates, matches Python dict comprehension.
      for (var i = 0; i < symbols.length; i++) symbols[i]: i,
    };
    final nChannels = (config['n_channels'] as num).toInt();
    final maxText = (config['MAX_TEXT'] as num).toInt();

    final gzBytes = await File(dictPath).readAsBytes();
    final dictText = utf8.decode(gzip.decode(gzBytes));
    final dictionary = <String, String>{};
    for (final line in const LineSplitter().convert(dictText)) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      dictionary[line.substring(0, tab)] = line.substring(tab + 1);
    }

    final embBytes = await File(embeddingPath).readAsBytes();
    final embBd = ByteData.sublistView(embBytes);
    final embeddingTable = Float32List(embBytes.length ~/ 4);
    for (var i = 0; i < embeddingTable.length; i++) {
      embeddingTable[i] = embBd.getFloat32(i * 4, Endian.little);
    }

    return MatchaTextFrontend(
      symbolToId: symbolToId,
      dictionary: dictionary,
      embeddingTable: embeddingTable,
      nChannels: nChannels,
      maxText: maxText,
      locale: profile.locale,
      neuralG2p: neuralG2p,
    );
  }

  /// text -> frontend input. G2P is dictionary-first: OOV words route
  /// through [neuralG2p] when wired, else throw [StateError].
  @override
  MatchaFrontendInput encode(String text) {
    // --- normalize: text -> tagged tokens (words + preserved symbols) ---
    final normalizer = TtsTextNormalizer.forLocale(
      locale,
      symbolToId.keys.toSet(),
    );
    final tokens = normalizer.normalize(text);

    // --- G2P: tokens -> IPA (dictionary first, neural fallback, else throw) ---
    final ipa = StringBuffer();
    for (final tok in tokens) {
      if (tok is SymbolToken) {
        ipa.write(tok.symbol);
      } else if (tok is WordToken) {
        final hit = dictionary[tok.word];
        if (hit != null) {
          ipa.write(hit);
        } else if (neuralG2p != null) {
          ipa.write(neuralG2p!(tok.word));
        } else {
          throw StateError(
            'MatchaTextFrontend: OOV word "${tok.word}" and no neural '
            'resolver wired.',
          );
        }
      }
    }

    // --- IPA chars -> symbol ids ---
    final pids = <int>[];
    for (final rune in ipa.toString().runes) {
      final ch = String.fromCharCode(rune);
      final id = symbolToId[ch];
      if (id != null) {
        pids.add(id);
      } else {
        throw StateError(
          'MatchaTextFrontend: IPA symbol "$ch" (U+${rune.toRadixString(16)}) '
          'is not in the 178-symbol table — cannot synthesize "$text".',
        );
      }
    }
    if (pids.isEmpty) {
      throw StateError(
        'MatchaTextFrontend: no symbols mapped for "$text" — cannot '
        'synthesize (all IPA characters were outside the symbol table).',
      );
    }

    final realLen = 2 * pids.length + 1;
    if (realLen > maxText) {
      throw StateError(
        'MatchaTextFrontend: chunk needs $realLen slots > MAX_TEXT $maxText '
        '(chunk before encode). Text: "$text".',
      );
    }

    // --- blank-interspersed ids[maxText] + tmask[maxText] ---
    final ids = List<int>.filled(maxText, 0);
    for (var i = 0; i < pids.length; i++) {
      final pos = 1 + 2 * i;
      ids[pos] = pids[i];
    }
    final textMask = Float32List(maxText);
    for (var t = 0; t < maxText; t++) {
      textMask[t] = t < realLen ? 1.0 : 0.0;
    }

    // --- host emb.bin gather -> [maxText * nChannels] ---
    final symbolEmbeddings = Float32List(maxText * nChannels);
    for (var t = 0; t < maxText; t++) {
      final srcBase = ids[t] * nChannels;
      final dstBase = t * nChannels;
      for (var c = 0; c < nChannels; c++) {
        symbolEmbeddings[dstBase + c] = embeddingTable[srcBase + c];
      }
    }

    return MatchaFrontendInput(symbolEmbeddings, textMask, realLen);
  }
}
