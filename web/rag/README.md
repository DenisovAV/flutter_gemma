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
- Reads `litert_embeddings_api.js` (source file)
- Bundles all dependencies (LiteRT.js, SentencePiece.js, TensorFlow.js)
- Outputs to `dist/` directory:
  - `litert_embeddings.js` - Main embedding module
  - `litert-*.js` - LiteRT.js runtime
  - `sentencepiece-*.js` - Tokenizer module
  - `tensorflow-*.js` - TensorFlow.js backend

**Build time:** ~10-30 seconds (depends on your machine)

### Step 3: Copy to Your Web App

**Option A: Example App (if testing flutter_gemma example)**

> **ℹ️ Note for plugin users:** The example app already includes pre-built JS files in the repository, so you can run it immediately without building. This step is only needed if you're modifying the embedding source code.

```bash
# Copy built files to example app (only if you modified litert_embeddings_api.js)
cp dist/* ../../example/web/
```

**Option B: Your Own Flutter Project**

```bash
# Copy to your project's web directory
cp dist/* <your_flutter_project>/web/
```

**Example:**
```bash
# If your project is at ~/my_flutter_app/
cp dist/* ~/my_flutter_app/web/
```

### Step 4: Add Script Tag to index.html

Open your project's `web/index.html` and add this line **before** the closing `</head>` tag:

```html
<head>
  <!-- ... other head content ... -->

  <!-- LiteRT.js Embeddings (for flutter_gemma web support) -->
  <script type="module" src="litert_embeddings.js"></script>
</head>
```

**Important:** The script must use `type="module"` and be placed in the `<head>` section.

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
├── README.md                 # This file
├── package.json              # NPM dependencies
├── package-lock.json         # Locked dependency versions
├── vite.config.js            # Vite build configuration
├── litert_embeddings_api.js  # Source code for embedding API
├── node_modules/             # Installed dependencies (after npm install)
└── dist/                     # Built output (after npm run build)
    ├── litert_embeddings.js
    ├── litert-*.js
    ├── sentencepiece-*.js
    └── tensorflow-*.js
```

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
2. ✅ Copied files: `cp dist/* <your_project>/web/`
3. ✅ Added script tag: `<script type="module" src="litert_embeddings.js"></script>` in `index.html`
4. ✅ Restart Flutter: `flutter run -d chrome` (hot reload won't load new scripts)

### Models download but embeddings fail

**Check:**
- Browser console for errors (`F12` → Console tab)
- Make sure you're using embedding models (not inference models)
- Verify model and tokenizer files are both downloaded

---

## 🚫 What This Is NOT

This is **NOT for RAG (vector search)** on web.

**Platform Support:**
- ✅ **Embeddings on web**: Fully supported (this build)
- ✅ **RAG on Android/iOS**: Fully supported (uses SQLite)
- ❌ **RAG on web**: NOT implemented (use Android/iOS instead)

If you need vector search (RAG), use Android or iOS platforms.

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
