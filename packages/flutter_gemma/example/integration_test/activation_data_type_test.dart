/// `activationDataType` regression: Gemma 4 copying figures out of a long
/// prompt on the GPU.
///
/// At the default activation type (FLOAT16 on GPU, and what the published
/// Gemma 4 `.litertlm` files ask for) GPUs scramble digits once the prompt is
/// long, the same way on every run: asked when a delivery arrived
/// (`2026/06/23`), E2B answers `2026/12/7` on an M3 Max and `20206/12/7` on an
/// iPhone 11; E4B answers `20226/12/17` on an M3 Max and a Snapdragon 8 Elite.
/// `ActivationDataType.float32` fixes it (LiteRT-LM#2814 on Metal, #3012 on
/// Adreno).
///
/// The prompt is a made-up delivery log, identical on every run: 64 lines,
/// about 3,100 tokens, each line with two dates and two amounts. Three
/// questions make the model copy some of them back. On an Apple M3 Max, E2B
/// and E4B at the default precision copied every figure right with logs of up
/// to 32 lines (~1,600 tokens) and wrong from 48 lines (~2,300). A Snapdragon 8
/// Elite got this 64-line log wrong with E4B, and other prompts wrong from
/// ~2,100 tokens.
///
/// An answer is SCRAMBLED when it holds a figure that is nowhere in the log:
/// that is the bug. A real figure from the wrong line is the model misreading
/// (E2B does it now and then at any precision), so it is printed, not counted.
///
/// On native targets both tests check that the GPU started, since the engine
/// falls back to CPU quietly and the CPU does not show the bug.
/// - float32 must scramble nothing: that test asserts.
/// - The default's answers are printed, and only checked for being there,
///   since a GPU without the bug copies right either way. Its lines start with
///   `[default]`.
///
/// On web only the default test runs. The web engine does not read
/// `activationDataType` (`@litert-lm/core` 0.17 has no such setting), runs the
/// `-web.litertlm` files on its own GPU executor, and reports no backend.
///
/// Gemma 4 E2B by default; pass `--dart-define=GEMMA4=E4B` for E4B (native
/// only: the E4B web file is over 2 GB).
///
/// Prerequisites (otherwise the model is downloaded: E2B 2.59 GB, E4B 3.66 GB,
/// E2B web 2.01 GB):
///   macOS:   gemma-4-E2B-it.litertlm in ~/Library/Containers/.../Documents/
///   Android: adb push gemma-4-E2B-it.litertlm /data/local/tmp/flutter_gemma_test/
///   iOS, web: downloaded via FlutterGemma.installModel()
///
/// Run: flutter test integration_test/activation_data_type_test.dart -d <device>
/// Web: flutter run -d chrome -t integration_test/activation_data_type_test.dart
///   (or flutter drive -d web-server with chromedriver, like the other web
///   tests). On Chrome 153 with WebGPU on an M3 Max, nothing was scrambled.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'inference_test_helpers.dart' show registerTestEngines;

/// E2B or E4B.
const _variant = String.fromEnvironment('GEMMA4', defaultValue: 'E2B');
const _file = 'gemma-4-$_variant-it.litertlm';

/// The web engine takes only the `-web.litertlm` build of each model.
String get _url =>
    'https://huggingface.co/litert-community/gemma-4-$_variant-it-litert-lm/'
    'resolve/main/${kIsWeb ? 'gemma-4-$_variant-it-web.litertlm' : _file}';

String? get _localPath {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return '/data/local/tmp/flutter_gemma_test/$_file';
  if (Platform.isMacOS) {
    return '${Platform.environment['HOME']}/Library/Containers/'
        'dev.flutterberlin.flutterGemmaExample55/Data/Documents/$_file';
  }
  return null;
}

Future<void>? _installed;

/// Installs the model once per run. Called from each test body rather than a
/// setUp, so a failure to install fails the test that needed it.
Future<void> _install() => _installed ??= () async {
  await registerTestEngines();
  final local = _localPath;
  final builder = FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  );
  if (local != null && File(local).existsSync()) {
    await builder.fromFile(local).install();
  } else {
    await builder.fromNetwork(_url).install();
  }
}();

/// One line of the made-up log.
typedef _Delivery = ({
  String id,
  String shipped,
  String arrived,
  int kilograms,
  int total,
});

/// [count] deliveries from a fixed seed, so every run and every device reads
/// the same log.
List<_Delivery> _deliveries(int count) {
  var seed = 7;
  int next(int bound) {
    // seed * 1103515245 + 12345, mod 2^31, with the multiplier (0x41C64E6D)
    // split so no product passes 2^53: on web a plain product loses bits and
    // the log would differ from native.
    seed =
        (seed * 0x4E6D + ((seed * 0x41C6) & 0x7FFF) * 0x10000 + 12345) &
        0x7fffffff;
    return seed % bound;
  }

  String two(int n) => n.toString().padLeft(2, '0');
  return [
    for (var i = 0; i < count; i++)
      () {
        final year = 2026 + next(2);
        final month = 1 + next(12);
        final day = 1 + next(19);
        return (
          id: 'D-${4100 + i * 7}',
          shipped: '$year/${two(month)}/${two(day)}',
          arrived: '$year/${two(month)}/${two(day + 2 + next(8))}',
          kilograms: 100 + next(9900),
          total: 1000 + next(99000),
        );
      }(),
  ];
}

String _logText(List<_Delivery> log) => [
  'Delivery log. One line per delivery: id, date shipped, date arrived, '
      'weight, invoice total.',
  for (final d in log)
    '${d.id} | shipped ${d.shipped} | arrived ${d.arrived} | '
        '${d.kilograms} kg | ${d.total} EUR',
].join('\n');

/// Three questions about [log], each with the figures a right answer holds.
List<({String text, List<String> figures})> _questions(List<_Delivery> log) {
  final a = log[log.length * 3 ~/ 4];
  final b = log[log.length ~/ 2];
  final lines = log.sublist(log.length - 6, log.length - 2);
  return [
    (
      text:
          'When did delivery ${a.id} arrive? Answer with the date only, '
          'exactly as it is written in the log.',
      figures: [a.arrived],
    ),
    (
      text:
          'What are the weight and the invoice total of delivery ${b.id}? '
          'Answer with the two numbers only.',
      figures: ['${b.kilograms}', '${b.total}'],
    ),
    (
      text:
          'Copy the lines for deliveries ${lines.first.id} to '
          '${lines.last.id} exactly as they are written in the log.',
      figures: [
        for (final d in lines) ...[
          d.shipped,
          d.arrived,
          '${d.kilograms}',
          '${d.total}',
        ],
      ],
    ),
  ];
}

/// Every figure in [text]: each run of digits joined by `/`, kept when it is a
/// date or has three digits or more. Whole runs, so `2026/06/233` is not read
/// as a right `2026/06/23`.
Iterable<String> _figures(String text) => RegExp(r'\d+(?:/\d+)*')
    .allMatches(text)
    .map((m) => m[0]!)
    .where((f) => f.contains('/') || f.length >= 3);

/// Asks every question in a fresh greedy session, and returns one line per
/// scrambled answer: one holding a figure that is nowhere in the log.
Future<List<String>> _askAll(ActivationDataType? type) async {
  final label = type?.name ?? 'default';
  final log = _deliveries(64);
  final text = _logText(log);
  final inLog = _figures(text).toSet();
  final model = await FlutterGemma.getActiveModel(
    maxTokens: 4096,
    preferredBackend: PreferredBackend.gpu,
    activationDataType: type,
  );
  final wrong = <String>[];
  try {
    // The web engine reports no backend; it runs only on WebGPU.
    if (!kIsWeb) {
      expect(
        model.activeBackend,
        PreferredBackend.gpu,
        reason: 'the GPU did not start, so this device cannot show the bug',
      );
    }
    for (final q in _questions(log)) {
      final session = await model.createSession(topK: 1, maxOutputTokens: 512);
      try {
        final prompt = '$text\n\n${q.text}';
        final tokens = await session.sizeInTokens(prompt);
        await session.addQueryChunk(Message(text: prompt, isUser: true));
        final answer = (await session.getResponse()).trim();
        expect(answer, isNotEmpty, reason: 'no answer to: ${q.text}');
        final got = _figures(answer).toSet();
        final missing = [
          for (final f in q.figures)
            if (!got.contains(f)) f,
        ];
        final invented = [
          for (final f in got)
            if (!inLog.contains(f)) f,
        ];
        final verdict = invented.isNotEmpty
            ? 'SCRAMBLED'
            : missing.isNotEmpty
            ? 'misread (a real figure from another line)'
            : 'right';
        debugPrint(
          // On web sizeInTokens is an estimate from the length.
          '[$label] ${kIsWeb ? '~' : ''}$tokens tokens: ${q.text}\n'
          '[$label]   $verdict: $answer'
          '${missing.isEmpty ? '' : '\n[$label]   missing: $missing'}'
          '${invented.isEmpty ? '' : '\n[$label]   not in the log: $invented'}',
        );
        if (invented.isNotEmpty) {
          wrong.add('${q.text} -> not in the log $invented');
        }
      } finally {
        await session.close();
      }
    }
  } finally {
    await model.close();
  }
  return wrong;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('default activations on GPU: answers printed, not asserted', (
    tester,
  ) async {
    await _install();
    final wrong = await _askAll(null);
    debugPrint(
      wrong.isEmpty
          ? '[default] nothing scrambled: this GPU does not show the bug'
          : '[default] ${wrong.length} of 3 answers scrambled: this GPU shows '
                'the bug${kIsWeb ? '' : ' that float32 fixes'}',
    );
  }, timeout: const Timeout(Duration(minutes: 30)));

  testWidgets(
    'float32 activations scramble no figure from a long prompt',
    (tester) async {
      await _install();
      final wrong = await _askAll(ActivationDataType.float32);
      expect(wrong, isEmpty);
    },
    // The web engine does not read activationDataType, so this would run the
    // default again.
    skip: kIsWeb,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
