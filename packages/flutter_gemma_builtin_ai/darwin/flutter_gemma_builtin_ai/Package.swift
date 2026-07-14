// swift-tools-version: 5.9
// Swift Package Manager manifest for flutter_gemma_builtin_ai (iOS + macOS,
// shared darwin source). Coexists with flutter_gemma_builtin_ai.podspec — both
// read the same Sources/ tree, so CocoaPods and SPM stay in sync.
import PackageDescription

let package = Package(
  name: "flutter_gemma_builtin_ai",
  platforms: [
    .iOS("16.0"),
    .macOS("10.15"),
  ],
  products: [
    // type: .static — Flutter's generated plugin package is static; without it
    // SPM links a .dylib (embedding/codesign + App Store validation pain).
    // Matches the core flutter_gemma package's manifests.
    .library(
      name: "flutter-gemma-builtin-ai",
      type: .static,
      targets: ["flutter_gemma_builtin_ai"]
    )
  ],
  dependencies: [
    // Flutter's SPM integration vends a single FlutterFramework package for
    // both iOS and macOS (it provides the Flutter / FlutterMacOS module per
    // platform); there is no separate FlutterMacOS SPM package.
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "flutter_gemma_builtin_ai",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      linkerSettings: [
        // FoundationModels is iOS 26 / macOS 26 only, but the package builds
        // from the iOS 16 / macOS 10.15 floor — every use is behind
        // `#available`. Weak-link it so binaries load on older OSes (the
        // CocoaPods podspec does this via `s.weak_frameworks`). SPM has no
        // first-class weak-framework setting, so pass the linker flag directly.
        .unsafeFlags([
          "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
        ])
      ]
    )
  ]
)
