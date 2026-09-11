# Platform setup for flutter_gemma

Entries each platform needs before a model will load. Without them the app
builds and then fails at model load, or is killed for memory.

- [Android](#android)
- [iOS](#ios)
- [macOS](#macos)
- [Windows and Linux](#windows-and-linux)
- [Web](#web)

## Android

`android/app/build.gradle.kts` (or `build.gradle`):

```
android {
    defaultConfig {
        minSdk = 30
    }
}
```

`minSdk 30` covers everything built on `.litertlm`: inference, embeddings and
speech. On API 29 the native library fails to load at runtime — the build does
not catch it. MediaPipe `.task` models run on lower API levels.

`android/app/src/main/AndroidManifest.xml` needs the internet permission to
download a model. Flutter's template declares it only for debug and profile
builds, so without this line the release build cannot download:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Only `arm64-v8a` is shipped for `.litertlm`. The OpenCL manifest entries the GPU
backend needs are merged in by the plugin; nothing to add.

## iOS

Minimum iOS 15.0 — 16.0 if the app includes `flutter_gemma_mediapipe`.

With CocoaPods, in `ios/Podfile`, declared once:

```ruby
platform :ios, '15.0'   # '16.0' if the app includes flutter_gemma_mediapipe
use_frameworks! :linkage => :static
```

With Swift Package Manager — the default since Flutter 3.44 — there is no
Podfile. Set **iOS Deployment Target** on the Runner target in Xcode instead, or
the build fails with `requires minimum platform version 15.0`.
`flutter_gemma_mediapipe` has no `Package.swift`, so an app using it gets a
Podfile as well; set the platform there too.

In Xcode, under **Signing & Capabilities**, add **Extended Virtual Addressing**
and **Increased Memory Limit**. That writes these keys to
`ios/Runner/Runner.entitlements` and links the file to the target — a file
edited by hand but not linked does nothing. Without them large models are
killed for memory:

```xml
<key>com.apple.developer.kernel.extended-virtual-addressing</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

The iOS Simulator cannot run GPU inference; use CPU there, or a real device.

## macOS

Add to both `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

`disable-library-validation` lets the app load the bundled native frameworks;
`network.client` lets it download the model. Add them to both files — the debug
and release builds read different ones.

`.litertlm` on macOS also needs a build phase that copies the LiteRT-LM
companion libraries into the app. Paste this into `macos/Podfile`, replacing any
existing `post_install` block, then run `pod install`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end

  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_targets.each do |user_target|
      phase_name = '[flutter_gemma] Setup LiteRT-LM macOS'

      unless user_target.name == 'Runner'
        user_target.build_phases
          .select { |p| p.respond_to?(:name) && p.name == phase_name }
          .each { |p| user_target.build_phases.delete(p) }
        next
      end

      existing = user_target.shell_script_build_phases.find { |p| p.name == phase_name }
      phase = existing || user_target.new_shell_script_build_phase(phase_name)
      phase.input_paths = [
        '$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Frameworks/LiteRtLm.framework/Versions/A/LiteRtLm',
      ]
      phase.output_paths = ['$(DERIVED_FILE_DIR)/flutter_gemma_litertlm_macos.stamp']
      phase.shell_script = <<~SHELL
        set -e
        STAGER="${HOME}/Library/Caches/flutter_gemma/native/macos_arm64/stage_macos_companions.sh"
        if [ ! -f "${STAGER}" ]; then
          echo "[flutter_gemma] ERROR: ${STAGER} not found." >&2
          echo "  flutter_gemma_litertlm 1.6.2+ installs it there from its build hook." >&2
          echo "  Upgrade the package, then: flutter clean && flutter pub get" >&2
          exit 1
        fi
        sh "${STAGER}" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
        mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
        touch "${SCRIPT_OUTPUT_FILE_0}"
      SHELL
    end
  end
end
```

Without it the build succeeds and the model fails to load at runtime.

## Windows and Linux

Nothing to add to the project. The native libraries — including the Windows GPU
shader compiler and NPU runtime — are bundled at build time.

- Windows: end users need the Microsoft Visual C++ Redistributable 2019 or later.
- Linux: building needs `clang cmake ninja-build libgtk-3-dev lld`. GPU needs the
  vendor Vulkan driver; Mesa's `llvmpipe` software fallback cannot run Gemma 4.

## Web

All script tags go in `web/index.html` `<head>`, before Flutter boots.

`.litertlm` engine:

```html
<script type="module">
window.litertLmReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/@litert-lm/core@0.17.0/+esm');
  window.Engine = m.Engine;
  return m.Engine;
})();
</script>
```

Model storage helpers. Copy `cache_api.js` and `opfs_helper.js` from the
`flutter_gemma` package's `web/` directory into the app's `web/`, then:

```html
<script src="cache_api.js"></script>
<script src="opfs_helper.js"></script>
```

Find the package directory with
`grep -A1 '"name": "flutter_gemma"' .dart_tool/package_config.json`.

Storage mode, set in `FlutterGemma.initialize(webStorageMode: ...)`:

| `WebStorageMode` | Use for |
| --- | --- |
| `cacheApi` (default) | models under about 2 GB |
| `streaming` | larger models — streams through OPFS |
| `none` | no persistence; downloads every launch |

The `.litertlm` web engine loads the web build of a model —
`gemma-4-E2B-it-web.litertlm` (2.0 GB, so use `streaming`), not
`gemma-4-E2B-it.litertlm`. It is text-only: no images, audio or LoRA, and no
Gemma 4 thinking.

A `--dart-define` token is compiled into `main.dart.js`, where every visitor can
read it. Serve web users a model from a repo that needs no token.
