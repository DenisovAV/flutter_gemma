# Flutter Gemma Example App

## Setup

### 1. Configure HuggingFace Token

Copy the config template and add your token:

```bash
cp config.json.example config.json
```

Edit `config.json` and add your HuggingFace token:

```json
{
  "HUGGINGFACE_TOKEN": "hf_your_token_here"
}
```

Get your token from: https://huggingface.co/settings/tokens

### 2. Run the App

**With configuration:**
```bash
flutter run --dart-define-from-file=config.json
```

**Without configuration** (token will be empty):
```bash
flutter run
```

### 3. Build for Production

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
