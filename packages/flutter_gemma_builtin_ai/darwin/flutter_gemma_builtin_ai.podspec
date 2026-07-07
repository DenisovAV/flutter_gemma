#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_gemma_builtin_ai.podspec` to validate before publishing.
#
# Single shared Darwin source set (darwin/Classes/**) drives BOTH the iOS and
# macOS plugins via Flutter's `sharedDarwinSource: true` (declared in
# pubspec.yaml). One podspec, one Classes directory — the `s.ios.*` / `s.osx.*`
# scoping picks the right Flutter dependency and deployment target per platform.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_gemma_builtin_ai'
  s.version          = '0.1.0'
  s.summary          = 'Apple Foundation Models backend for flutter_gemma (iOS/macOS).'
  s.description      = <<-DESC
Built-in OS AI engine for flutter_gemma: Apple Foundation Models on
iOS 26+/macOS 26+ (text; image input on OS 27+). Runtime-gated; the pod
builds from iOS 16 / macOS 10.15.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/flutter_gemma'
  s.license          = { :file => '../../flutter_gemma/LICENSE' }
  s.author           = { 'Flutter Berlin' => 'flutter@flutterberlin.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '10.15'
  # FoundationModels only exists on iOS 26+/macOS 26+, so it must be WEAK-linked
  # for the pod to load on the iOS 16 / macOS 10.15 floor. All uses are gated at
  # runtime with `if #available(iOS 26.0, macOS 26.0, *)`.
  s.weak_frameworks  = 'FoundationModels'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.9'
end
