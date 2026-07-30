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

import 'package:flutter_gemma/core/utils/gemma_log.dart';

import 'tts_frontend_input.dart';

/// Pure-Dart Matcha-TTS text frontend: dictionary G2P + blank-intersperse +
/// host-side embedding gather. No neural fallback — OOV words throw.
class TtsTextFrontend {
  /// Pure constructor from already-parsed data (unit-testable, no file I/O).
  TtsTextFrontend({
    required this.symbolToId,
    required this.dictionary,
    required this.embeddingTable,
    required this.nChannels,
    required this.maxText,
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

  /// Parse the real Matcha bundle files: `config.json` (symbols +
  /// n_channels + MAX_TEXT), `g2p_dict.txt.gz` (gzipped word -> IPA
  /// dictionary), `emb.bin` (little-endian f32 phoneme embedding table).
  static Future<TtsTextFrontend> load({
    required String configPath,
    required String dictPath,
    required String embeddingPath,
  }) async {
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

    return TtsTextFrontend(
      symbolToId: symbolToId,
      dictionary: dictionary,
      embeddingTable: embeddingTable,
      nChannels: nChannels,
      maxText: maxText,
    );
  }

  /// text -> frontend input. Throws [StateError] on an OOV word (this
  /// frontend is dictionary-only; the neural `dp_g2p` fallback needs FFI and
  /// belongs to `TtsCore`).
  MatchaFrontendInput encode(String text) {
    // --- G2P: text -> IPA (dictionary path only) ---
    final hasTrailingPeriod = text.endsWith('.');
    final core = hasTrailingPeriod ? text.substring(0, text.length - 1) : text;
    final words = core.trim().split(RegExp(r'\s+'));
    final ipaParts = <String>[];
    for (final w in words) {
      final wordIpa = dictionary[w.toLowerCase()];
      if (wordIpa == null) {
        throw StateError(
          'OOV word "$w" — neural dp_g2p fallback not yet wired '
          '(dictionary-only frontend)',
        );
      }
      ipaParts.add(wordIpa);
    }
    final ipa = ipaParts.join(' ') + (hasTrailingPeriod ? '.' : '');

    // --- IPA chars -> symbol ids ---
    final pids = <int>[];
    for (final rune in ipa.runes) {
      final ch = String.fromCharCode(rune);
      final id = symbolToId[ch];
      if (id != null) {
        pids.add(id);
      } else {
        gemmaLog('⚠️  TtsTextFrontend: dropping unmapped IPA symbol "$ch"');
      }
    }
    if (pids.isEmpty) {
      throw StateError(
        'TtsTextFrontend: no symbols mapped for "$text" — cannot synthesize '
        '(all IPA characters were outside the symbol table).',
      );
    }

    // --- blank-interspersed ids[maxText] + tmask[maxText] ---
    final ids = List<int>.filled(maxText, 0);
    for (var i = 0; i < pids.length; i++) {
      final pos = 1 + 2 * i;
      if (pos < maxText) ids[pos] = pids[i];
    }
    final realLen = 2 * pids.length + 1;
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
