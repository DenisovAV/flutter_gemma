/// Where the LiteRT.js WASM runtime is fetched from on web.
///
/// Web embeddings run through LiteRT.js, which loads a WASM runtime
/// (`litert_wasm_internal.js` + a ~9 MB `.wasm`) at the first embedding call.
/// No pub package can ship those bytes, so until 2.2.0 this pointed at
/// `/wasm/` — a path nothing served, which made web embeddings fail for every
/// consumer with `Failed to load LiteRT model: undefined`.
///
/// The default is now the pinned CDN copy, measured working in Chrome:
/// jsDelivr serves it with `Access-Control-Allow-Origin: *`,
/// `Cross-Origin-Resource-Policy: cross-origin` and `application/wasm`, which
/// is what LiteRT.js needs (it sets `crossOrigin = "anonymous"` on the script
/// it injects, so a host without CORS fails even for the `.js`).
///
/// **The version pin is load-bearing.** `web/litert.js` is one half of a pair:
/// it is the JS glue built against a specific `@litertjs/core`, and it calls
/// that release's WASM entry points by name. 0.2.x called
/// `loadAndCompileWebGpu`, which 2.x replaced with `loadModel` + `compileModel`
/// — feed one half a runtime from the other and it fails with
/// `loadAndCompileWebGpu is not defined`. Both halves are rebuilt together from
/// `tool/web_build`, so this pin moves when that build does.
///
/// Serve it yourself — offline, an air-gapped deploy, or a CSP that forbids
/// third-party script — by copying `node_modules/@litertjs/core/wasm/` into
/// the app's `web/wasm/` and setting the prefix before the first embedding:
///
/// ```dart
/// LiteRtWebRuntime.wasmPath = '/wasm/';
/// ```
///
/// A trailing slash is required: LiteRT.js appends the file name to it, and the
/// prefix is root-absolute — an app served under a base href other than `/`
/// needs the full path (`/my-app/wasm/`) or an absolute URL.
///
/// Set it BEFORE the first embedding. The runtime is loaded once and cached
/// behind a flag in `litert_embeddings.js`, so a later assignment is ignored
/// without an error.
///
/// Setting this on a native platform is harmless and has no effect.
abstract final class LiteRtWebRuntime {
  /// The `@litertjs/core` release this package is built against.
  static const pinnedVersion = '2.5.3';

  /// Prefix the WASM runtime is loaded from. See [LiteRtWebRuntime].
  static String wasmPath =
      'https://cdn.jsdelivr.net/npm/@litertjs/core@$pinnedVersion/wasm/';
}
