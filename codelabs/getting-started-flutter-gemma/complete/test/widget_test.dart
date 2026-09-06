import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_quickstart/download_page.dart';
import 'package:gemma_quickstart/model.dart';

void main() {
  // `isModelInstalled` is keyed by file name, so a file name that drifts from
  // its URL means the app re-downloads a model it already has — silently.
  test('every model id matches the last segment of its URL', () {
    for (final model in [Models.gemma3, Models.qwen3]) {
      expect(model.fileName, model.url.split('/').last, reason: model.label);
    }
  });

  testWidgets('the download screen offers the model before any plugin call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadPage(model: Models.qwen3, onInstalled: () {}),
      ),
    );
    expect(find.text('Qwen3 0.6B'), findsOneWidget);
    expect(find.text('Download model'), findsOneWidget);
  });
}
