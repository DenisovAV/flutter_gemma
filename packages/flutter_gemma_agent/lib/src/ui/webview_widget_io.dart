import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Native (`dart:io`) build of the embedded [WebviewResult] renderer.
///
/// `flutter_inappwebview` has a platform implementation on Android, iOS, macOS
/// and Windows, so an inline [InAppWebView] renders the skill's page in-tree.
/// The plugin is imported ONLY through this conditional-export seam (this file
/// on native, `webview_widget_web.dart` on web) so the web build never pulls the
/// plugin's web arm (which has no JS bridge). The caller gates this on a
/// supported platform; on an unsupported native target it shows the external
/// "Open" card instead of reaching here.
Widget buildInlineWebview(String url, {double aspectRatio = 4 / 3}) {
  return AspectRatio(
    aspectRatio: aspectRatio,
    child: InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
      ),
    ),
  );
}
