// Regression test for #250 (Mode 2): AssetSource install on desktop must
// fall back to in-memory `loadAsset → writeFile` when `large_file_handler`'s
// native channel call surfaces a `MissingPluginException`.
//
// Before 0.14.5, FlutterAssetLoader.copyAssetToFile wrapped *all* exceptions
// (including MissingPluginException) in a generic `Exception(...)`, so the
// upstream `on MissingPluginException` catch in AssetSourceHandler matched
// by type and never fired — the desktop install path threw a wrapped
// exception instead of falling back.
//
// Run: flutter test integration_test/asset_source_desktop_test.dart -d macos
//
// On macOS / Windows / Linux there is no large_file_handler plugin
// implementation, so the channel call throws MissingPluginException —
// the exact bug Erik reported in #250 on Windows.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AssetSource install falls back to writeFile on desktop',
      (t) async {
    await FlutterGemma.initialize();

    // assets/test/test_image.jpg is a 14 KB fixture bundled in the example.
    // Re-using it as a stand-in "model" file: AssetSourceHandler doesn't
    // care about contents, only that copy succeeds and it's registered.
    const fixturePath = 'assets/test/test_image.jpg';
    const fixtureBasename = 'test_image.jpg';

    // Ensure clean state — uninstall if a prior run left it around.
    final wasInstalled = await FlutterGemma.isModelInstalled(fixtureBasename);
    if (wasInstalled) {
      await FlutterGemma.uninstallModel(fixtureBasename);
    }

    // The actual probe — installing from an asset on macOS must not throw
    // "_Exception: Failed to copy asset: ... - MissingPluginException(...)".
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromAsset(fixturePath)
        .install();

    // Verify the file actually landed in app docs dir (the writeFile fallback
    // wrote it).
    final docsDir = await getApplicationDocumentsDirectory();
    final installed = File('${docsDir.path}/$fixtureBasename');
    expect(installed.existsSync(), isTrue,
        reason: 'Asset should have been written to app docs dir');
    expect(installed.lengthSync(), greaterThan(0),
        reason: 'Written file should be non-empty');

    // Cleanup.
    await FlutterGemma.uninstallModel(fixtureBasename);
  });
}
