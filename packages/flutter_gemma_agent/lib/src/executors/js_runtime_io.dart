import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'js_skill_executor.dart';

/// The native ([dart:io]) [JsRuntime] factory — selected by the conditional
/// export in `js_runtime.dart` on every native target. The `flutter_inappwebview`
/// import lives ONLY in this file; the web build resolves `js_runtime_web.dart`
/// instead and never pulls the plugin's broken web arm.
JsRuntime createJsRuntime() => _InAppWebViewJsRuntime();

/// Real [JsRuntime] backed by `flutter_inappwebview`'s [HeadlessInAppWebView].
///
/// Asset skills are served over a loopback HTTP server and loaded via
/// `http://127.0.0.1:<port>/index.html`. `http://127.0.0.1` is a W3C
/// "potentially trustworthy" SECURE CONTEXT, so the skill's `crypto.subtle`
/// (Web Crypto) is defined and its sibling `index.js` loads via a relative URL
/// from the real origin. This is the only mechanism that grants a secure
/// context for local content on ALL native engines (WebView2 ignores
/// `loadData`'s baseUrl; WKWebView's `loadFile` can't read sibling files) —
/// verified on hardware across Windows/Android/macOS/iOS.
///
/// The webview is a sandbox: JavaScript on, a single result handler as the only
/// native bridge, and a `shouldOverrideUrlLoading` policy that blocks navigation
/// off the loopback origin. `flutter_inappwebview` is imported only here (the
/// native arm); the web arm runs a `package:web` iframe instead.
class _InAppWebViewJsRuntime implements JsRuntime {
  @override
  Future<String> run({
    required JsSkillSource source,
    required String dataJson,
    required String secret,
    required Duration timeout,
  }) async {
    final completer = Completer<String>();
    HeadlessInAppWebView? headless;
    _SkillAssetServer? server;
    var injected = false;

    // Resolve the URL the webview will navigate to, and (for asset skills) the
    // loopback server that serves the skill folder under it.
    final String pageUrl;
    switch (source) {
      case AssetJsSource(:final assetKey):
        server = await _SkillAssetServer.start(assetKey);
        pageUrl = server.entryUrl;
      case UrlJsSource(:final url):
        pageUrl = url;
    }

    headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: false,
        transparentBackground: true,
      ),
      // The controller is only valid from onWebViewCreated onward — register the
      // single result handler here (the documented-safe moment).
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: resultChannel,
          callback: (args) {
            final message = args.isNotEmpty ? args.first?.toString() ?? '' : '';
            if (!completer.isCompleted) completer.complete(message);
            return null;
          },
        );
      },
      // Surface page console output to the host log (diagnostics only).
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('JsSkillExecutor[js]: ${consoleMessage.message}');
      },
      // Inject once the page has finished loading; the native arm passes
      // web:false so the wrapper posts via callHandler.
      onLoadStop: (controller, url) async {
        if (injected) return;
        injected = true;
        try {
          await controller.evaluateJavascript(
            source: buildInjectionScript(dataJson, secret, web: false),
          );
        } catch (e) {
          if (!completer.isCompleted) {
            completer.complete(jsonEncode({'error': 'injection failed: $e'}));
          }
        }
      },
      // Sandbox: allow loads of the skill's own origin/page; deny navigation
      // elsewhere so the foreign page cannot redirect off the loopback origin.
      // NOT wired on Windows: the Windows arm's shouldOverrideUrlLoading is
      // undocumented and CRASHES the headless WebView2 (verified — L2 exit 79;
      // the probe without this callback ran fine). On Windows the sandbox rests
      // on the loopback server serving only the skill folder (path traversal
      // blocked) + the single result handler being the only native bridge.
      shouldOverrideUrlLoading: Platform.isWindows
          ? null
          : (controller, navigationAction) async {
              final target = navigationAction.request.url?.toString();
              if (!injected) {
                if (target == null ||
                    target == pageUrl ||
                    (server != null && target.startsWith(server.origin))) {
                  return NavigationActionPolicy.ALLOW;
                }
              }
              return NavigationActionPolicy.CANCEL;
            },
    );

    try {
      await headless.run();
      final controller = headless.webViewController;
      if (controller == null) {
        throw StateError('headless webview controller unavailable');
      }
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(pageUrl)));

      return await completer.future.timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('JS skill did not respond', timeout),
      );
    } finally {
      await headless.dispose();
      await server?.close();
    }
  }
}

/// A loopback HTTP server that serves a single JS skill's bundled asset folder
/// over `http://127.0.0.1:<port>/`. Files are read from [rootBundle] (the skill
/// ships as Flutter assets, not as on-disk files), so a `GET /index.js` maps to
/// the asset sibling of the skill's `index.html`. Bound to loopback only with an
/// ephemeral port; the secure-context "potentially trustworthy" origin is what
/// makes `crypto.subtle` work.
class _SkillAssetServer {
  _SkillAssetServer._(this._server, this._assetDir, this._entryName);

  final HttpServer _server;

  /// The bundled-asset directory prefix (with trailing slash) the skill lives
  /// in, e.g. `assets/skills/calculate-hash/scripts/`.
  final String _assetDir;

  /// The entry file name within [_assetDir], e.g. `index.html`.
  final String _entryName;

  /// `http://127.0.0.1:<port>` — the skill's secure origin.
  String get origin => 'http://127.0.0.1:${_server.port}';

  /// The full URL to load in the webview, e.g. `http://127.0.0.1:1234/index.html`.
  String get entryUrl => '$origin/$_entryName';

  static Future<_SkillAssetServer> start(String htmlAssetKey) async {
    final slash = htmlAssetKey.lastIndexOf('/');
    final assetDir = slash == -1 ? '' : htmlAssetKey.substring(0, slash + 1);
    final entryName = slash == -1
        ? htmlAssetKey
        : htmlAssetKey.substring(slash + 1);

    final httpServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final server = _SkillAssetServer._(httpServer, assetDir, entryName);
    httpServer.listen(server._handle);
    return server;
  }

  Future<void> _handle(HttpRequest req) async {
    // Map the request path to a bundled asset under the skill's directory.
    // Strip the leading slash and any query; default `/` to the entry file.
    var path = req.uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    if (path.isEmpty) path = _entryName;
    // Block path traversal out of the skill directory.
    if (path.contains('..')) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final assetKey = '$_assetDir$path';
    try {
      final data = await rootBundle.load(assetKey);
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = _contentTypeFor(path)
        ..add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      req.response.statusCode = HttpStatus.notFound;
    }
    await req.response.close();
  }

  static ContentType _contentTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'html' || 'htm' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' => ContentType('application', 'json', charset: 'utf-8'),
      'svg' => ContentType('image', 'svg+xml'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'wasm' => ContentType('application', 'wasm'),
      _ => ContentType.binary,
    };
  }

  Future<void> close() => _server.close(force: true);
}
