#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma_builtin_ai.podspec` to validate before publishing.
#
# Single shared Darwin source set (darwin/flutter_gemma_builtin_ai/Sources/**)
# drives BOTH the iOS and macOS plugins via Flutter's `sharedDarwinSource: true`
# (declared in pubspec.yaml). CocoaPods and Swift Package Manager both read that
# same Sources/ tree; the `s.ios.*` / `s.osx.*` scoping picks the right Flutter
# dependency and deployment target per platform.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma_builtin_ai'
  s.version          = '0.2.0'
  s.summary          = 'Apple Foundation Models backend for flutter_gemma (iOS/macOS).'
  s.description      = <<-DESC
Built-in OS AI engine for flutter_gemma: Apple Foundation Models on
iOS 26+/macOS 26+ (text; image input on OS 27+). Runtime-gated; the pod
builds from iOS 15 / macOS 10.15.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/flutter_gemma'
  s.license          = { :file => '../../flutter_gemma/LICENSE' }
  s.author           = { 'Flutter Berlin' => 'flutter@flutterberlin.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_gemma_builtin_ai/Sources/flutter_gemma_builtin_ai/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  # iOS 15.0, not 16.0 (#441): no Foundation Models symbol is reachable without
  # an availability check — 26.0 for the session APIs, 26.4 for `tokenCount` —
  # and no stored property of the plugin class has an FM type (`sessions` is
  # `[Int64: Any]`), so 16 only kept apps off iOS 15 for nothing.
  # 15.0 is also the lowest FREE floor: this package uses `Task` / `async` /
  # `for try await`, and Swift Concurrency is native from iOS 15.0 — measured, a
  # Runner at 13.0 gains `libswift_Concurrency.dylib` in Frameworks/ (+7.7 MB)
  # and one at 15.0 does not. Lowering it is possible, it just costs that.
  # NOTE the macOS floor below is 10.15 while macOS's concurrency floor is 12.0,
  # so every macOS consumer already pays it. Raising osx to 12.0 would be free
  # (Foundation Models needs macOS 26 regardless) but is out of #441's scope.
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '10.15'
  # FoundationModels only exists on iOS 26+/macOS 26+, so it must be WEAK-linked
  # for the pod to load on the iOS 15 / macOS 10.15 floor. Every use is behind an
  # availability check (26.0, or 26.4 for tokenCount); the few FM-typed helpers
  # are gated by an `@available` declaration attribute and only ever reached from
  # inside a runtime check.
  s.weak_frameworks  = 'FoundationModels'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.9'
end
