import 'dart:io' as io;

/// True on Linux, where the JS executor has no webview implementation. Used by
/// the L2 test to skip the real-webview scenarios (S1–S5) and assert S6's
/// ErrorResult instead.
bool get isLinux => io.Platform.isLinux;
