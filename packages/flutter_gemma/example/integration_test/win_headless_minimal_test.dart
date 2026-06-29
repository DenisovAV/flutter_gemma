// Isolation test v2: does a WebViewEnvironment with a writable userDataFolder
// fix the Windows headless crash? Default WebView2 user-data is `<exe>\WebView2`
// which can be read-only under the integration-test build dir → access
// violation. If THIS passes (with the env), the Windows crash is fixable and the
// real arm should adopt the same env — making Windows behave like macOS.
import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _html = '''
<!DOCTYPE html><html><body><script>
window.flutter_inappwebview.callHandler('R', JSON.stringify({
  secure: isSecureContext, hasSubtle: !!(window.crypto && window.crypto.subtle)
}));
</script></body></html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'headless webview with a writable WebViewEnvironment',
    (t) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_html);
        req.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/index.html';

      // A writable per-run user-data folder (the suspected crash cause: the
      // default `<exe>\WebView2` may be read-only under the test build dir).
      final dataDir = await Directory.systemTemp.createTemp('wv2_probe_');
      WebViewEnvironment? env;
      if (Platform.isWindows) {
        env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(userDataFolder: dataDir.path),
        );
      }

      final completer = Completer<String>();
      HeadlessInAppWebView? headless;
      headless = HeadlessInAppWebView(
        webViewEnvironment: env,
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
        onWebViewCreated: (c) {
          c.addJavaScriptHandler(
            handlerName: 'R',
            callback: (args) {
              if (!completer.isCompleted) {
                completer.complete(args.isNotEmpty ? '${args.first}' : '');
              }
              return null;
            },
          );
        },
      );

      try {
        await headless.run();
        await headless.webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
        final raw = await completer.future.timeout(const Duration(seconds: 30));
        expect(raw, contains('"hasSubtle":true'), reason: raw);
      } finally {
        await headless.dispose();
        await env?.dispose();
        await server.close(force: true);
        try {
          await dataDir.delete(recursive: true);
        } catch (_) {}
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
