# Flutter Gemma Example App

## Setup

### 1. Configure HuggingFace Token (Optional)

⚠️ **Note:** HuggingFace token is required for **Gemma and Meta models only**:

**Token Required (gated repos):**
- All Gemma models (Gemma 3 Nano, 1B, 270M)
- All EmbeddingGemma models
- Llama 3.2 1B, Hammer 2.1 0.5B

**Token NOT Required (public repos):**
- DeepSeek R1, Phi-4, TinyLlama, Qwen 2.5
- All Gecko embedding models
- Local asset models (if you have files)

**Most models in the app work without a token!** Configure it only if you need Gemma/Meta models:

**Step 1:** Copy the config template:
```bash
cp config.json.example config.json
```

**Step 2:** Edit `config.json` and add your HuggingFace token:
```json
{
  "HUGGINGFACE_TOKEN": "hf_your_token_here"
}
```

**Step 3:** Get your token from: https://huggingface.co/settings/tokens

**Step 4:** Grant access to gated repos:
- Visit model page (e.g., https://huggingface.co/google/gemma-3n-E2B-it-litert-preview)
- Click "Request Access" button

### 2. Run the App

**With configuration:**
```bash
flutter run --dart-define-from-file=config.json
```

**Without configuration** (works for public and local models):
```bash
flutter run
```

### 3. Local Models Setup (Optional)

If you want to test local models like `Gemma 3 1B IT (Local)`:

1. Download the model file from HuggingFace
2. Place it in the appropriate location:
   - **Android:** `android/app/src/main/assets/models/gemma3-1b-it-int4.task`
   - **iOS:** Add to Xcode project under Resources
   - **Web:** `web/assets/models/gemma3-1b-it-int4.task` (production builds only)
3. Ensure the file is listed in `pubspec.yaml` under `flutter: assets:`

```yaml
flutter:
  assets:
    - assets/models/gemma3-1b-it-int4.task
    - assets/models/gemma-3n-E2B-it-int4.task
```

### 4. Build for Production

```bash
flutter build apk --dart-define-from-file=config.json
flutter build ios --dart-define-from-file=config.json
flutter build web --dart-define-from-file=config.json
```

## Security Notes

- ⚠️ **Never commit `config.json`** - it contains your private token
- ✅ `config.json.example` is the template (safe to commit)
- ✅ `config.json` is in `.gitignore` (automatically excluded)

## Testing

The app includes integration tests for:
- Model downloads (public and private)
- Asset model loading
- Bundled model loading
- Inference and embedding generation
