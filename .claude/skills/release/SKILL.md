---
name: release
description: Release flutter_gemma — rebuild JAR, update all version numbers, checksums, CHANGELOG, upload to GitHub release
user_invocable: true
---

# Flutter Gemma Release

Complete release checklist for flutter_gemma plugin. Run as `/release <version>` (e.g. `/release 0.14.0`).

## Pre-flight

Before starting, verify you're on the correct branch and all changes are committed:
```bash
git status
git log --oneline -5
```

## Step 1: Update version numbers

All files that contain the version:

| File | Variable/Field | Example |
|------|---------------|---------|
| `pubspec.yaml` | `version:` | `version: 0.14.0` |
| `litertlm-server/build.gradle.kts` | `version =` | `version = "0.14.0"` |
| `CLAUDE.md` | `Current Version:` | `- **Current Version**: 0.14.0` |
| `macos/scripts/setup_desktop.sh:61` | `JAR_VERSION=` | `JAR_VERSION="0.14.0"` |
| `macos/scripts/prepare_resources.sh:42` | `JAR_VERSION=` | `JAR_VERSION="0.14.0"` |
| `linux/scripts/setup_desktop.sh:62` | `JAR_VERSION=` | `JAR_VERSION="0.14.0"` |
| `windows/scripts/setup_desktop.ps1:90` | `$JarVersion =` | `$JarVersion = "0.14.0"` |

> JAR_URL is auto-derived from JAR_VERSION in all scripts — no separate update needed.

## Step 2: Update CHANGELOG.md

Add new section at top with all changes. Categories: features, fixes, breaking changes.

## Step 3: Build JAR

```bash
cd litertlm-server && ./gradlew fatJar
```

Verify build success. JAR output: `litertlm-server/build/libs/litertlm-server-<VERSION>-all.jar`

## Step 4: Compute new SHA256

```bash
shasum -a 256 litertlm-server/build/libs/litertlm-server-*-all.jar
```

## Step 5: Update JAR checksums in all 4 scripts

| File | Variable |
|------|----------|
| `macos/scripts/setup_desktop.sh:63` | `JAR_CHECKSUM="<sha256>"` |
| `macos/scripts/prepare_resources.sh:44` | `JAR_CHECKSUM="<sha256>"` |
| `linux/scripts/setup_desktop.sh:64` | `JAR_CHECKSUM="<sha256>"` |
| `windows/scripts/setup_desktop.ps1:92` | `$JarChecksum = "<sha256>"` |

JAR is cross-platform (JVM bytecode) — same checksum for all platforms.

## Step 6: Verify

```bash
flutter analyze    # 0 errors
flutter test       # all pass
dart pub publish --dry-run   # 0 warnings
```

**NEVER publish without dry-run first.** Publishing is IRREVERSIBLE.

## Step 7: Create/update GitHub release

```bash
# Create new release
gh release create v<VERSION> \
  litertlm-server/build/libs/litertlm-server-<VERSION>-all.jar \
  --title "v<VERSION>" \
  --notes-file CHANGELOG_EXCERPT.md

# OR update existing release (delete old JAR first)
gh release delete-asset v<VERSION> litertlm-server.jar --yes 2>/dev/null
gh release upload v<VERSION> litertlm-server/build/libs/litertlm-server-<VERSION>-all.jar
```

Verify JAR URL returns 200:
```bash
curl -sI "https://github.com/DenisovAV/flutter_gemma/releases/download/v<VERSION>/litertlm-server.jar" | head -1
```

## Step 8: Commit & PR

- Author: `--author="Sasha Denisov <denisov.shureg@gmail.com>"`
- No AI attribution in commit messages
- No "Co-Authored-By" or "Generated with Claude" footers
- Create PR via `gh pr create`

## Step 9: After merge — publish

```bash
dart pub publish --dry-run   # verify one more time
dart pub publish             # only after user approval!
```
