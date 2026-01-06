# Contributing to flutter_gemma

First off, **thank you** for considering contributing to `flutter_gemma`! 🎉

This project brings on-device LLM capabilities (Gemma, DeepSeek, Qwen, Phi, etc.) to Flutter applications across mobile, web, and desktop platforms. Your contributions help make AI more accessible and privacy-preserving for everyone.

---

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Get Started](#how-to-get-started)
- [Types of Contributions](#types-of-contributions)
- [Development Workflow](#development-workflow)
- [Project Structure](#project-structure)
- [Coding Guidelines](#coding-guidelines)
- [Platform-Specific Notes](#platform-specific-notes)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Questions?](#questions)

---

## Code of Conduct

By participating in this project, you agree to maintain a respectful and professional environment. We are committed to providing a harassment-free experience for everyone, regardless of background or experience level.

If you experience or witness unacceptable behavior, please open an issue or contact the maintainer privately.

---

## How to Get Started

### Prerequisites

**Required:**
- Flutter **3.24.0** or higher
- Dart **3.4.0** or higher
- Platform-specific toolchains:
  - **Android**: Android Studio / Android SDK
  - **iOS**: Xcode 14+, CocoaPods 1.11+
  - **Web**: Modern browser (Chrome/Firefox recommended)
  - **Desktop**:
    - **macOS**: Xcode, CocoaPods (Apple Silicon only)
    - **Windows**: Visual Studio 2019/2022 with "Desktop development with C++" workload, PowerShell 5.1+
    - **Linux**: GCC 9+ or Clang 10+, CMake 3.14+ (planned)

**Optional but Recommended:**
- Hugging Face account + token (for testing gated models like Gemma 3 Nano, EmbeddingGemma)
- Good internet connection (models can be 300MB - 3GB+)

### Setup Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/DenisovAV/flutter_gemma.git
   cd flutter_gemma
   flutter pub get
   ```

2. **Run the example app:**
   ```bash
   cd example
   flutter pub get
   
   # Run on your preferred platform:
   flutter run -d chrome       # Web
   flutter run -d android      # Android
   flutter run -d ios          # iOS
   flutter run -d windows      # Windows
   flutter run -d macos        # macOS
   ```

3. **Follow platform-specific setup:**
   - See `README.md` for general setup instructions
   - See `DESKTOP_SUPPORT.md` for desktop-specific setup
   - See `WEB_CACHING_PROGRESS_FIX.md`, `LINUX_DESKTOP_PLAN.md`, `WINDOWS_GPU_VM_SETUP.md` for platform-specific details

---

## Types of Contributions

We welcome contributions in many forms:

### 🐛 Bug Fixes & Improvements
- Fix issues reported in the issue tracker
- Improve error messages and user experience
- Address technical debt items in `TODO.md`
- Performance optimizations

### ✨ Features
- Support for new models
- Desktop platform features (embeddings, VectorStore/RAG)
- Quality-of-life improvements in the example app
- New API methods or utilities

### 📚 Documentation
- Clarify confusing setup steps
- Add "how-to" guides for common tasks
- Improve code comments and docstrings
- Update platform-specific documentation

### 🧪 Testing
- Add unit tests for new features
- Improve integration test coverage
- Test edge cases and error scenarios
- Cross-platform testing

---

## Development Workflow

### 1. Find or Create an Issue

- Check existing issues for something that interests you
- Look for labels like `good first issue` or `help wanted`
- For **non-trivial changes**, please open an issue first to discuss the approach

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

Use descriptive branch names:
- `fix/web-auth-content-length`
- `feat/linux-desktop-support`
- `docs/improve-desktop-setup`
- `test/add-vector-store-tests`

### 3. Make Your Changes

- Keep changes **focused** - prefer multiple small PRs over one large PR
- Follow existing code style and patterns
- Write clear commit messages
- Update documentation if needed

### 4. Run Linting & Tests

```bash
# Run analyzer
flutter analyze

# Run tests
flutter test

# Run example app integration tests
cd example
flutter test integration_test
```

### 5. Commit Your Changes

```bash
git add .
git commit -m "feat: add HTTP HEAD support for public URLs"
```

Use conventional commit messages:
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation
- `test:` for tests
- `refactor:` for code refactoring
- `chore:` for maintenance tasks

---

## Project Structure

Understanding the codebase layout will help you contribute effectively:

```
flutter_gemma/
├── lib/
│   ├── core/                    # Core functionality
│   │   ├── api/                 # Public API (FlutterGemma class)
│   │   ├── handlers/            # Model source handlers
│   │   ├── infrastructure/      # Download, storage, web services
│   │   ├── model_management/    # Model installation & management
│   │   └── ...                  # Models, messages, tools, etc.
│   ├── mobile/                  # Mobile platform implementation
│   ├── web/                     # Web platform implementation
│   ├── desktop/                 # Desktop platform implementation
│   └── flutter_gemma.dart       # Main entry point
├── example/                     # Example application
│   ├── lib/                     # Example app code
│   └── integration_test/        # Integration tests
├── test/                        # Unit tests
├── litertlm-server/             # Kotlin/JVM server for desktop
├── web/                         # Web-specific JS files
└── [platform]/                  # Platform-specific code (macos/, windows/, linux/)
```

**Key Files to Know:**
- `lib/flutter_gemma.dart` - Main public API
- `lib/core/api/flutter_gemma.dart` - Modern API implementation
- `lib/mobile/flutter_gemma_mobile.dart` - Mobile implementation
- `lib/web/flutter_gemma_web.dart` - Web implementation
- `lib/desktop/flutter_gemma_desktop.dart` - Desktop implementation

---

## Coding Guidelines

### Style

- Follow Dart/Flutter style guide
- Use meaningful variable and function names
- Keep functions focused and small
- Add comments for complex logic
- Prefer composition over inheritance

### Public API Changes

Any changes to public APIs should:
- Maintain backward compatibility when possible
- Be documented in `README.md`
- Include usage examples
- Be tested thoroughly

**Public API locations:**
- `lib/flutter_gemma.dart`
- `lib/core/api/flutter_gemma.dart`
- `lib/flutter_gemma_interface.dart`

### Error Handling

- Use clear, actionable error messages
- Prefer typed exceptions (`UnsupportedError`, `StateError`, etc.)
- Don't expose sensitive information (tokens, file paths) in errors
- Handle platform-specific errors gracefully

### Platform Consistency

- Keep behavior consistent across platforms when possible
- If a feature isn't supported on a platform, throw `UnsupportedError` with a clear message
- Document platform limitations in `README.md`

---

## Platform-Specific Notes

### Desktop Contributions

If you're working on desktop support:

1. **Read the documentation:**
   - `DESKTOP_SUPPORT.md` - Complete desktop guide
   - `LINUX_DESKTOP_PLAN.md` - Linux-specific plans

2. **Understand the architecture:**
   - Desktop uses gRPC to communicate with a Kotlin/JVM server
   - Server code is in `litertlm-server/`
   - Client code is in `lib/desktop/`

3. **Test your changes:**
   - Test on macOS (Apple Silicon) and/or Windows x64
   - Verify JRE download and server startup work correctly
   - Check that models initialize and inference works

### Web Contributions

If you're working on web support:

1. **Understand web limitations:**
   - GPU backend only (CPU not supported by MediaPipe)
   - Models stored in IndexedDB/Cache API
   - No local file system access

2. **Test considerations:**
   - Test with both public and authenticated (token) downloads
   - Verify CORS handling
   - Check browser compatibility (Chrome, Firefox, Safari)

### Mobile Contributions

If you're working on mobile:

1. **Test on both platforms:**
   - Android (various API levels)
   - iOS (16.0+)

2. **Consider memory constraints:**
   - Large models may not work on low-end devices
   - Test with different model sizes

---

## Testing

### Unit Tests

Add tests in `test/` directory:

```dart
// test/core/model_management/model_manager_test.dart
void main() {
  test('should install model from network', () async {
    // Your test code
  });
}
```

### Integration Tests

Add integration tests in `example/integration_test/`:

```dart
// example/integration_test/my_feature_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  testWidgets('my feature test', (tester) async {
    // Your test code
  });
}
```

### Running Tests

```bash
# All unit tests
flutter test

# Specific test file
flutter test test/core/model_management/model_manager_test.dart

# Integration tests
cd example
flutter test integration_test
```

### Test Coverage

Aim for:
- **New features**: Add tests for happy path and error cases
- **Bug fixes**: Add regression tests
- **Critical paths**: Model installation, inference, embeddings

---

## Pull Request Process

### Before Submitting

- [ ] Code builds successfully on at least one platform
- [ ] `flutter analyze` passes with no errors
- [ ] `flutter test` passes
- [ ] New features have tests
- [ ] Documentation is updated (if needed)
- [ ] Commit messages follow conventional commits

### PR Description Template

```markdown
## Description
Brief description of what this PR does.

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring
- [ ] Test addition

## Testing
- [ ] Tested on Android
- [ ] Tested on iOS
- [ ] Tested on Web
- [ ] Tested on Desktop (macOS/Windows)

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Tests added/updated
```

### Review Process

1. Maintainer will review your PR
2. Address any feedback or requested changes
3. Once approved, your PR will be merged
4. Thank you for contributing! 🎉

---

## Good First Issues

Looking for a place to start? Check out:

1. **`TODO.md`** - Technical debt and improvement opportunities
   - Save `contentLength` for authenticated web downloads
   - Extract duplicated progress simulation code
   - Add HTTP HEAD support for public URLs

2. **Documentation improvements:**
   - Add more examples to `README.md`
   - Improve platform-specific setup guides
   - Add troubleshooting tips

3. **Testing:**
   - Add tests for edge cases
   - Improve integration test coverage
   - Test on different platforms/devices

4. **Example app:**
   - Add new demo screens
   - Improve error handling UX
   - Add more function calling examples

---

## Questions?

- **Not sure how to implement something?** Open an issue with your question
- **Want feedback before coding?** Create a draft PR or open a discussion
- **Found a bug?** Open an issue with reproduction steps
- **Have a feature idea?** Open an issue to discuss it first

---

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

**Thank you for contributing to flutter_gemma!** 🙌

Every contribution, no matter how small, makes a difference. We appreciate your time and effort!

