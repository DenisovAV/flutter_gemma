import 'dart:async';
import 'dart:convert';

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
/// Configures the webview as a sandbox: JavaScript on, a single result handler
/// as the only bridge, and a `shouldOverrideUrlLoading` policy that blocks any
/// navigation away from the loaded page. The `flutter_inappwebview` import lives
/// only here (the native arm); the web arm runs a `package:web` iframe instead.
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

    // The initial page URL we allow (URL skills); asset skills load as inline
    // HTML under about:blank, so there is no allowed remote URL.
    final pageUrl = source is UrlJsSource ? source.url : null;
    var injected = false;

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
      // Sandbox: allow the initial requested page; deny every other navigation
      // so the foreign page cannot redirect to file:// or another origin.
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final target = navigationAction.request.url?.toString();
        if (!injected) {
          if (pageUrl == null || target == pageUrl) {
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

      switch (source) {
        case AssetJsSource(:final assetKey):
          final html = await rootBundle.loadString(assetKey);
          // Inline the sibling index.js (if the HTML references it) so iOS/macOS
          // (allowingReadAccessTo: nil under loadData) can still run the skill.
          final js = await _loadSiblingJs(assetKey, html);
          await controller.loadData(
            data: inlineSkillHtml(html, js),
            mimeType: 'text/html',
            baseUrl: WebUri('about:blank'),
          );
        case UrlJsSource(:final url):
          await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      }

      return await completer.future.timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('JS skill did not respond', timeout),
      );
    } finally {
      await headless.dispose();
    }
  }

  /// Reads the sibling `index.js` for an asset skill whose [html] references it.
  /// Returns an empty string when the JS is already inline (no reference), so
  /// [inlineSkillHtml] is a no-op.
  Future<String> _loadSiblingJs(String htmlAssetKey, String html) async {
    if (!html.contains('index.js')) return '';
    final slash = htmlAssetKey.lastIndexOf('/');
    final jsKey = slash == -1
        ? 'index.js'
        : '${htmlAssetKey.substring(0, slash + 1)}index.js';
    try {
      return await rootBundle.loadString(jsKey);
    } catch (_) {
      // No sibling JS bundled (or a cross-origin <script src>): leave as-is.
      return '';
    }
  }
}
