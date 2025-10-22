# GitHub Workflows

This directory contains GitHub Actions workflows for CI/CD automation.

## Workflows

### 🧪 [`test.yml`](workflows/test.yml) - CI Tests
Runs on every push/PR to `main` or `develop`:
- ✅ Code analysis (`flutter analyze`)
- ✅ Unit tests with coverage
- ✅ Android example APK build
- ✅ iOS example build (unsigned)

**Status:** [![CI Tests](https://github.com/DenisovAV/flutter_gemma/actions/workflows/test.yml/badge.svg)](https://github.com/DenisovAV/flutter_gemma/actions/workflows/test.yml)

---

### 🚀 [`release.yml`](workflows/release.yml) - Release Build
Runs when you push a tag `v*.*.*`:
- ✅ Builds release APK
- ✅ Creates GitHub Release
- ✅ Attaches APK to release
- ✅ Auto-generates release notes

**Status:** [![Release Build](https://github.com/DenisovAV/flutter_gemma/actions/workflows/release.yml/badge.svg)](https://github.com/DenisovAV/flutter_gemma/actions/workflows/release.yml)

---

## 📖 Full Documentation

See [CICD.md](CICD.md) for complete documentation including:
- How to create releases
- Test organization
- Troubleshooting guide
- Configuration options
- Future enhancements

---

## Quick Start

### Create a Release

```bash
# 1. Update version
vim pubspec.yaml  # version: 0.11.8

# 2. Update changelog
vim CHANGELOG.md

# 3. Commit and tag
git add pubspec.yaml CHANGELOG.md
git commit -m "Bump version to 0.11.8"
git push origin main

git tag v0.11.8
git push origin v0.11.8

# 4. GitHub Actions will automatically:
#    - Build APK
#    - Create release
#    - Attach APK
```

### Run Tests Locally

```bash
# All tests
flutter test

# With coverage
flutter test --coverage

# Specific test file
flutter test test/core/model_source_test.dart
```

---

## 📝 Notes

- APK artifacts are kept for 7 days (CI) or 90 days (releases)
- Coverage is uploaded to Codecov (optional)
- All unit tests run on every push/PR

---

## 🔧 Configuration Files

- `workflows/test.yml` - CI test workflow
- `workflows/release.yml` - Release workflow
- `CICD.md` - Full documentation

---

## 🆘 Need Help?

- Check [CICD.md](CICD.md) for troubleshooting
- View workflow runs in [Actions tab](https://github.com/DenisovAV/flutter_gemma/actions)
- Report issues in [GitHub Issues](https://github.com/DenisovAV/flutter_gemma/issues)
