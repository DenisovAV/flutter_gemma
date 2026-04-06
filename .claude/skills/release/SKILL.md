---
name: release
description: Release flutter_gemma — update versions, checksums, CHANGELOG, optionally rebuild JAR, upload to GitHub release
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

## Step 1: Check if server changed

```bash
git diff main -- litertlm-server/src/
```

If **no changes** in `litertlm-server/src/` — skip Steps 3, 4, 5, 7 (JAR build, checksum, GitHub release upload). The existing JAR from the previous release is reused. Still update `JAR_VERSION` in scripts to match the **previous release version** that has the JAR (do NOT bump to new version).

If **server changed** — proceed with all steps.

## Step 2: Update version numbers

### Always update (plugin version):

| File | Variable/Field | Example |
|------|---------------|---------|
| `pubspec.yaml` | `version:` | `version: <VERSION>` |
| `ios/flutter_gemma.podspec` | `s.version` | `s.version = '<VERSION>'` |
| `CLAUDE.md` | `Current Version:` | `- **Current Version**: <VERSION>` |

### Only if server changed (JAR version):

| File | Variable/Field | Example |
|------|---------------|---------|
| `litertlm-server/build.gradle.kts` | `version =` | `version = "<VERSION>"` |
| `macos/scripts/setup_desktop.sh:61` | `JAR_VERSION=` | `JAR_VERSION="<VERSION>"` |
| `macos/scripts/prepare_resources.sh:42` | `JAR_VERSION=` | `JAR_VERSION="<VERSION>"` |
| `linux/scripts/setup_desktop.sh:62` | `JAR_VERSION=` | `JAR_VERSION="<VERSION>"` |
| `windows/scripts/setup_desktop.ps1:90` | `$JarVersion =` | `$JarVersion = "<VERSION>"` |

> JAR_URL is auto-derived from JAR_VERSION in all scripts — no separate update needed.
> If server didn't change, leave JAR_VERSION pointing to the last release that included a JAR rebuild.

## Step 3: Update CHANGELOG.md

Add new section at top with all changes. Categories: features, fixes, breaking changes.

## Step 4: Build JAR (only if server changed)

```bash
cd litertlm-server && ./gradlew fatJar
```

Verify build success. JAR output: `litertlm-server/build/libs/litertlm-server-<VERSION>-all.jar`

## Step 5: Compute new SHA256 (only if server changed)

```bash
shasum -a 256 litertlm-server/build/libs/litertlm-server-*-all.jar
```

## Step 6: Update JAR checksums (only if server changed)

| File | Variable |
|------|----------|
| `macos/scripts/setup_desktop.sh:63` | `JAR_CHECKSUM="<sha256>"` |
| `macos/scripts/prepare_resources.sh:44` | `JAR_CHECKSUM="<sha256>"` |
| `linux/scripts/setup_desktop.sh:64` | `JAR_CHECKSUM="<sha256>"` |
| `windows/scripts/setup_desktop.ps1:92` | `$JarChecksum = "<sha256>"` |

JAR is cross-platform (JVM bytecode) — same checksum for all platforms.

## Step 7: Verify

```bash
flutter analyze    # 0 errors
flutter test       # all pass
dart pub publish --dry-run   # 0 warnings
```

**NEVER publish without dry-run first.** Publishing is IRREVERSIBLE.

## Step 8: Create/update GitHub release (only if server changed)

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

## Step 9: Commit & PR

- Author: `--author="Sasha Denisov <denisov.shureg@gmail.com>"`
- No AI attribution in commit messages
- No "Co-Authored-By" or "Generated with Claude" footers
- Create PR via `gh pr create`

## Step 10: After merge — publish

```bash
dart pub publish --dry-run   # verify one more time
dart pub publish             # only after user approval!
```
