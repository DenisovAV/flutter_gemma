import 'dart:io' as io;

/// True on Linux, where the JS executor has no webview implementation. Used by
/// the L2 test to skip the real-webview scenarios (S1–S5) and assert S6's
/// ErrorResult instead.
bool get isLinux => io.Platform.isLinux;

/// True on Windows. `HeadlessInAppWebView` ACCESS-VIOLATION-crashes the
/// `flutter_inappwebview_windows` plugin under the `flutter test` integration
/// harness (proven: a minimal no-our-code headless test crashes identically,
/// while the same code as a `flutter run` app works). The loopback
/// secure-context mechanism itself IS proven on Windows WebView2 via the
/// standalone probe — only the test harness is incompatible — so the L2
/// real-webview scenarios are skipped here, not failed.
bool get isWindows => io.Platform.isWindows;
