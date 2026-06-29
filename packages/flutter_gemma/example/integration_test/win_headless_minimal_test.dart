// Isolation test: does a MINIMAL HeadlessInAppWebView + loopback loadUrl crash
// in the integration_test harness on Windows? This is exactly what the
// standalone probe did (which ran fine via `flutter run`) — but here inside
// `flutter test`. If THIS crashes (exit 79, c0000005), the fault is the
// integration_test × headless-WebView2 combination, NOT our JsSkillExecutor
// (macOS runs the real arm 6/6). If it passes, the crash is in our io arm and
// we dig there.
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
    'minimal headless webview over loopback does not crash',
    (t) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_html);
        req.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}/index.html';

      final completer = Completer<String>();
      HeadlessInAppWebView? headless;
      headless = HeadlessInAppWebView(
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
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
