// The registration surface an app actually uses: `FlutterGemma.initialize(
// inferenceEngines: [LiteRtLmEngine()])` registers LitertlmManifestResolver
// through HuggingFaceResolverSource, and `FlutterGemma.resolveHuggingFace`
// reaches it. Core's registry tests cover the probe chain with fakes; this
// file runs the FULL published init path with the real engine — offline, the
// resolver's fetch seam fed from the committed fixture snapshot.
//
// Reproduction notes (each is the kind of thing the next person loses an
// hour to):
// - `initialize()` ends in the model manager's restore, which reads
//   shared_preferences. Under `flutter test` that plugin has no host, so the
//   call throws MissingPluginException — unless
//   `SharedPreferences.setMockInitialValues({})` runs first, which swaps in
//   the in-memory store and lets the whole init path complete headless.
// - `resolveHuggingFace` derives the platform key from
//   `defaultTargetPlatform`, so pin it (`debugDefaultTargetPlatformOverride`)
//   or the expected row depends on whichever host runs the suite.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/engine_registry.dart';
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart';
import 'package:flutter_gemma/core/registry/hugging_face_resolver_registry.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show FlutterGemma;
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart'
    show LiteRtLmEngine;
import 'package:flutter_gemma_litertlm/src/manifest/litertlm_manifest_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _repo = 'litert-community/SmolLM3-3B';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture = jsonDecode(
    File(
      'test/manifest/fixtures/${_repo.replaceAll('/', '__')}.json',
    ).readAsStringSync(),
  );
  // What the reference reader picks for this repo on macOS with no hint —
  // the same row the offline sweep pins.
  final golden =
      (jsonDecode(
                File(
                  'test/manifest/fixtures/reference_goldens.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['$_repo|macos|-']
          as Map<String, dynamic>;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServiceRegistry.reset();
    EngineRegistry.instance.reset();
    HuggingFaceResolverRegistry.instance.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    HuggingFaceResolverRegistry.instance.reset();
    EngineRegistry.instance.reset();
    ServiceRegistry.reset();
  });

  // The full published init path — with prefs mocked it completes headless,
  // so registration is exercised exactly as an app runs it.
  Future<void> init({List<HuggingFaceResolver> resolvers = const []}) =>
      FlutterGemma.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
        huggingFaceResolvers: resolvers,
      );

  test(
    'registering the engine auto-registers LitertlmManifestResolver',
    () async {
      await init();
      expect(
        HuggingFaceResolverRegistry.instance.findFor(
          _repo,
          fileType: ModelFileType.litertlm,
        ),
        isA<LitertlmManifestResolver>(),
      );
    },
  );

  test('an explicit resolver wins the equal-priority tie over the '
      'engine-carried one', () async {
    var explicitFetches = 0;
    final explicit = LitertlmManifestResolver(
      fetch: (url, headers) async {
        explicitFetches++;
        return jsonEncode(fixture);
      },
    );
    await init(resolvers: [explicit]);
    expect(
      HuggingFaceResolverRegistry.instance.registered.length,
      2,
      reason: 'explicit + engine-carried',
    );

    final r = await FlutterGemma.resolveHuggingFace(
      _repo,
      fileType: ModelFileType.litertlm,
    );
    // The engine-carried instance (default fetcher → network) never saw the
    // request: the explicit one answered, from the fixture.
    expect(explicitFetches, 1);
    expect(r.file, golden['file']);
    expect(r.runtime.preferredBackend, PreferredBackend.gpu);
    expect(golden['backend'], 'gpu');
  });

  test('a const resolver passed both explicitly and via the engine registers '
      'once', () async {
    await init(resolvers: const [LitertlmManifestResolver()]);
    expect(
      HuggingFaceResolverRegistry.instance.registered
          .whereType<LitertlmManifestResolver>()
          .length,
      1,
    );
  });
}
