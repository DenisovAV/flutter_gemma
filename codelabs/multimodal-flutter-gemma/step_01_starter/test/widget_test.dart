import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_quickstart/download_page.dart';
import 'package:gemma_quickstart/model.dart';

void main() {
  // `isModelInstalled` is keyed by file name. `install()` skips bytes it
  // already has, so a name that drifts from its URL does not re-download — it
  // strands the app on a download screen the gate is never satisfied by. It is
  // a cheap mistake to make here and an expensive one to carry into Step 3,
  // where the same gate stands in front of 2.59 GB.
  test('the model id matches the last segment of its URL', () {
    const model = Models.smolVlm2;
    expect(model.fileName, model.url.split('/').last, reason: model.label);
  });

  testWidgets('the download screen offers the model before any plugin call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadPage(model: Models.smolVlm2, onInstalled: () {}),
      ),
    );
    expect(find.text('SmolVLM2 500M'), findsOneWidget);
    expect(find.text('Download model'), findsOneWidget);
  });
}
