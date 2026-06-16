# Web Embedding Support for flutter_gemma

This directory contains the build setup for **text embedding generation** on the **web platform**.

## 📌 What This Is

When you use `flutter_gemma` to generate embeddings on web, the plugin needs JavaScript libraries (LiteRT.js, SentencePiece.js, TensorFlow.js) to run the embedding models in the browser.

**This build step is ONLY for web embeddings.** Mobile platforms (Android/iOS) work out of the box.

---

## 🚀 Quick Start (For Flutter Developers)

If you've added `flutter_gemma` to your `pubspec.yaml` and want to use **embedding generation on web**, follow these steps:

### Prerequisites

- Node.js installed (download from [nodejs.org](https://nodejs.org))
- Your Flutter web project with `flutter_gemma` in `pubspec.yaml`

### Step 1: Install Dependencies

```bash
# Navigate to this directory
cd <your_flutter_gemma_package_path>/web/rag

# Install npm packages (one-time setup)
npm install
```

This will install:
- `@litertjs/core` - LiteRT.js for running TFLite models in browser
- `@sctg/sentencepiece-js` - Tokenizer for embedding models
- `@tensorflow/tfjs-core` + `@tensorflow/tfjs-backend-webgl` - TensorFlow.js dependencies
- `vite` - Build tool for bundling JavaScript modules

### Step 2: Build the Embedding Modules

```bash
# Build JavaScript modules
npm run build
```

**What this does:**
- Reads `litert_embeddings_api.js` and `sqlite_vector_store.js` (source files)
- Bundles all dependencies (LiteRT.js, SentencePiece.js, TensorFlow.js)
- Outputs everything required for runtime to `dist/`:
  - `litert_embeddings.js` - Main embedding module
  - `sqlite_vector_store.js` + `sqlite_vector_store_worker.js` - VectorStore (RAG)
  - `cache_api.js` - Hand-written helpers (`window.cacheHas/cachePut/cacheGet`)
    that the runtime requires; copied automatically from `web/cache_api.js`
  - `litert.js` / `sentencepiece.js` / `tensorflow.js` - Bundled runtimes
  - `wasm/` - LiteRT WASM runtime (`litert_wasm_internal.{js,wasm}` plus the
    threaded and compat variants)

The build script is cross-platform — it works on macOS, Linux, and Windows
(Git Bash / PowerShell / cmd) without any shell tricks.

**Build time:** ~10-30 seconds (depends on your machine).

### Step 3: Copy to Your Web App

**Option A: Example App (if testing flutter_gemma example)**

> **ℹ️ Note for plugin users:** The example app already includes pre-built JS files in the repository, so you can run it immediately without building. This step is only needed if you're modifying the embedding source code.

```bash
# Copy built files to example app (only if you modified litert_embeddings_api.js)
cp dist/* ../../example/web/
```

**Option B: Your Own Flutter Project**

```bash
# Copy the entire dist/ contents (preserve subdirectory structure for wasm/)
cp -r dist/* <your_flutter_project>/web/
```

This will place at the root of your `web/`: the JS modules, `cache_api.js`,
and a `wasm/` directory with the LiteRT WASM runtime.

### Step 4: Add Script Tags to index.html

Open your project's `web/index.html` and add these lines **before** the
closing `</head>` tag:

```html
<head>
  <!-- ... other head content ... -->

  <!-- flutter_gemma web support -->
  <!-- cache_api.js MUST come first and be a non-module script — it
       defines window.cacheHas / cachePut / cacheGet that the runtime
       calls during embedding init. -->
  <script src="cache_api.js"></script>
  <script type="module" src="litert_embeddings.js"></script>
  <script type="module" src="sqlite_vector_store.js"></script>
</head>
```

**Important:**
- `cache_api.js` is **NOT** a module — load it with a plain `<script src=...>`
  tag, before the module scripts. Without it the runtime fails with
  `NoSuchMethodError: tried to call a non-function: 'dart.global.cacheHas'`.
- The `wasm/` directory is loaded automatically by `litert_embeddings.js`
  from `/wasm/` — no script tag needed, just make sure the files are
  copied next to `index.html` under `web/wasm/`.

### Step 5: Run Your Flutter Web App

```bash
# From your Flutter project root
flutter run -d chrome
```

Now you can generate embeddings on web:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// Install embedding model
await FlutterGemma.installEmbedder()
  .modelFromNetwork(modelUrl, token: token)
  .tokenizerFromNetwork(tokenizerUrl)
  .install();

// Generate embeddings (works on web!)
final embeddingModel = await FlutterGemma.getActiveEmbedder();
final embedding = await embeddingModel.generateEmbedding('Hello, world!');
print('Dimensions: ${embedding.length}');
```

---

## 📂 Directory Structure

```
web/rag/
├── README.md                       # This file
├── package.json                    # NPM dependencies + build script
├── vite.config.js                  # Vite build configuration (main bundle)
├── vite.config.worker.js           # Vite build configuration (worker)
├── litert_embeddings_api.js        # Source code for embedding API
├── sqlite_vector_store.js          # Source code for VectorStore (SQLite WASM)
├── sqlite_vector_store_worker.js   # Source code for the SQLite worker
├── node_modules/                   # Installed dependencies (after npm install)
└── dist/                           # Built output (after npm run build)
    ├── litert_embeddings.js        # Embedding module
    ├── sqlite_vector_store.js      # VectorStore module
    ├── sqlite_vector_store_worker.js  # SQLite worker (includes wa-sqlite)
    ├── cache_api.js                # window.cacheHas/cachePut/cacheGet helpers
    ├── litert.js / sentencepiece.js / tensorflow.js  # Bundled runtimes
    └── wasm/
        ├── litert_wasm_internal.{js,wasm}
        ├── litert_wasm_threaded_internal.{js,wasm}
        └── litert_wasm_compat_internal.{js,wasm}
```

`cache_api.js` itself lives one level up at `<package>/web/cache_api.js`
(not in `web/rag/`); the build script copies it into `dist/` automatically.

---

## 🔧 Troubleshooting

### "npm: command not found"

**Solution:** Install Node.js from [nodejs.org](https://nodejs.org)

### Build fails with errors

**Solution:** Delete `node_modules` and reinstall:
```bash
rm -rf node_modules package-lock.json
npm install
npm run build
```

### Embeddings don't work on web

**Checklist:**
1. ✅ Built modules: `npm run build` in `web/rag/`
2. ✅ Copied files: `cp -r dist/* <your_project>/web/`
   (the `-r` matters — it preserves the `wasm/` subdirectory)
3. ✅ Added script tags in `index.html`, **with `cache_api.js` before
   the module scripts and as a plain `<script src=...>` (not module)**.
4. ✅ `wasm/` directory is at `<your_project>/web/wasm/` — verify
   `<your_project>/web/wasm/litert_wasm_internal.wasm` exists.
5. ✅ Restart Flutter: `flutter run -d chrome` (hot reload won't load
   new scripts).

### Common error messages

**`NoSuchMethodError: tried to call a non-function: 'dart.global.cacheHas'`**
→ `cache_api.js` is missing or loaded as a module. Use a plain
`<script src="cache_api.js"></script>` tag, no `type="module"`,
before the other scripts.

**`Failed to initialize LiteRT embeddings: ... Failed to load LiteRT model: undefined`**
→ The `wasm/` directory is missing or in the wrong place. Confirm
`<your_project>/web/wasm/litert_wasm_internal.{js,wasm}` exists.

### Models download but embeddings fail

**Check:**
- Browser console for errors (`F12` → Console tab)
- Make sure you're using embedding models (not inference models)
- Verify model and tokenizer files are both downloaded

---

## ✅ Full Platform Support

This build provides **both Embeddings AND VectorStore (RAG)** on web.

**Platform Support:**
- ✅ **Embeddings on web**: Fully supported (LiteRT.js + SentencePiece.js)
- ✅ **VectorStore on web**: Fully supported (SQLite WASM via wa-sqlite + OPFS)
- ✅ **RAG on Android/iOS**: Fully supported (native SQLite)

**Web VectorStore Features:**
- SQLite WASM (wa-sqlite) with OPFS storage
- 10x faster than IndexedDB (~10-20ms search in 1k vectors)
- Identical API to mobile (same Dart code works everywhere)
- Binary BLOB format (71% smaller than JSON)

---

## 🔄 When to Rebuild

You only need to rebuild if:
- You update `litert_embeddings_api.js` source file
- Flutter_gemma updates the embedding implementation
- You want to update dependencies (e.g., newer LiteRT.js version)

For normal development, one-time build is enough.

---

## 📚 Additional Resources

- **flutter_gemma Documentation**: [pub.dev/packages/flutter_gemma](https://pub.dev/packages/flutter_gemma)
- **LiteRT.js**: [github.com/google/litert](https://github.com/google/litert)
- **Embedding Models**: [HuggingFace litert-community](https://huggingface.co/litert-community)

---

## 💡 Tips

**Production Builds:**
```bash
# Build with minification for production
npm run build
```

**Development:**
```bash
# Watch mode (rebuilds on file changes)
npm run dev
```

**Clean Rebuild:**
```bash
rm -rf dist node_modules package-lock.json
npm install
npm run build
```

**File Sizes (after build):**
- `litert_embeddings.js` - ~4 KB
- `litert-*.js` - ~30 KB
- `sentencepiece-*.js` - ~720 KB
- `tensorflow-*.js` - ~900 KB

**Total:** ~1.6 MB (gzipped: ~400 KB when served with compression)

---

Need help? Check the [flutter_gemma GitHub issues](https://github.com/DenisovAV/flutter_gemma/issues)
