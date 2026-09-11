# Platform setup for flutter_gemma

Entries each platform needs before a model will load. Without them the app
builds and then fails at model load, or is killed for memory.

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

Only `arm64-v8a` is shipped for `.litertlm`. The OpenCL manifest entries the GPU
backend needs are merged in by the plugin; nothing to add.

## iOS

`ios/Podfile`, declared once:

```ruby
platform :ios, '15.0'   # '16.0' if the app includes flutter_gemma_mediapipe
use_frameworks! :linkage => :static
```

`ios/Runner/Runner.entitlements` — without these, large models are killed for
memory:

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
<key>com.apple.developer.kernel.extended-virtual-addressing</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

`disable-library-validation` lets the app load the bundled native frameworks;
`network.client` lets it download the model. Add them to both files — the debug
and release builds read different ones.

## Windows and Linux

Nothing to add. The native libraries — including the Windows GPU shader compiler
and NPU runtime — are bundled at build time.

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

Web is GPU-only. The `.litertlm` web engine is text-only: no images, audio,
thinking or LoRA.
