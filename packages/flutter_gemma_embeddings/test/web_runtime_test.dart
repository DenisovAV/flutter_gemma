import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    LiteRtWebRuntime.wasmPath =
        'https://cdn.jsdelivr.net/npm/@litertjs/core@'
        '${LiteRtWebRuntime.pinnedVersion}/wasm/';
  });

  // The pin is not cosmetic: `web/litert.js` is the JS half of the runtime and
  // calls the WASM entry points of the release it was built against. Mixing
  // halves fails at the first embedding ("loadAndCompileWebGpu is not defined"
  // when 0.2.x glue met a 2.x runtime — measured in Chrome 153). This has to
  // match what tool/web_build resolved.
  test('the pin matches the version web/litert.js was built against', () {
    expect(LiteRtWebRuntime.pinnedVersion, '2.5.3');
    expect(
      LiteRtWebRuntime.wasmPath,
      'https://cdn.jsdelivr.net/npm/@litertjs/core@2.5.3/wasm/',
    );
  });

  // LiteRT.js appends the file name to this prefix, so a missing trailing
  // slash silently requests `…/wasmlitert_wasm_internal.js`.
  test('the default ends in a slash', () {
    expect(LiteRtWebRuntime.wasmPath, endsWith('/'));
  });

  test('an app can point it at its own copy', () {
    LiteRtWebRuntime.wasmPath = '/wasm/';
    expect(LiteRtWebRuntime.wasmPath, '/wasm/');
  });
}
