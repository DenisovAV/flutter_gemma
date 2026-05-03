---
name: release
description: Release flutter_gemma — bump versions, optionally re-publish native prebuilts (iOS/macOS/Linux/Windows/Android dylibs) to GitHub Release, update SHA256 checksums in hook/build.dart, publish to pub.dev
user_invocable: true
---

# Flutter Gemma Release

Run as `/release <plugin-version>` (e.g. `/release 0.14.1`).

## Architecture context (read this first)

flutter_gemma 0.14.0+ has **no Kotlin/JVM/gRPC server**. Native libs come from one of two sources, decided per-platform by `hook/build.dart` (Native Assets):

1. **In-repo prebuilts** at `native/litert_lm/prebuilt/<os>_<arch>/` — these are checked in for **every supported platform** (iOS, macOS, Linux, Windows, Android). They are **excluded from the pub package** via `.pubignore` (`native/litert_lm/prebuilt/`). End users never see them; the hook downloads from GitHub Release on `pub get`.
2. **GitHub Release `native-v<NATIVE_VERSION>` archives** (e.g. `native-v0.10.2`) — these are the **canonical source for end users**. URL pattern: `litertlm-<os>_<arch>.tar.gz` flat archive of the matching `prebuilt/` folder.

Whether to bump `native-v<NATIVE_VERSION>` or re-publish the existing tag is the **central decision** of every release.

## Pre-flight

```bash
git status                  # all desired changes staged or already committed
git log --oneline -5
flutter analyze             # 0 errors
flutter test                # all pass
```

## Step 1: Determine release scope

Three independent dimensions — answer each:

### 1a. Plugin code changed?
```bash
git diff <last-tag> -- lib/ hook/ pubspec.yaml ios/flutter_gemma.podspec android/ web/
```
If yes → bump pub plugin version, publish to pub.dev. Always true for a release.

### 1b. Native dylibs changed (any platform)?
```bash
git diff <last-tag> -- native/litert_lm/prebuilt/
```
If **any** dylib changed → must re-publish GitHub Release archives **and** update SHA256 checksums in `hook/build.dart`, otherwise end users will keep getting the stale dylibs.

### 1c. patch_c_api.sh / build_*.sh / WORKSPACE patch changed?
This implies (1b) — verify dylibs were actually rebuilt against the new patches. If not, rebuild before continuing (see "Rebuild native dylibs" below).

## Step 2: Bump versions

Always:
| File | Field | Note |
|------|-------|------|
| `pubspec.yaml` | `version:` | the plugin version (e.g. `0.14.1`) |
| `ios/flutter_gemma.podspec` | `s.version` | match plugin version |
| `CLAUDE.md` | `Current Version:` line | match plugin version |

Only if (1b) bumps `NATIVE_VERSION`:
| File | Field |
|------|-------|
| `hook/build.dart` | `_nativeVersion` constant — bump (e.g. `'0.10.2'` → `'0.10.3'`) |

For App Store / breaking platform fixes prefer **bumping NATIVE_VERSION** rather than overwriting `native-v0.10.2` assets — keeps consumers on `0.14.0` reproducible. Overwrite only for emergency hotfixes where downstream version pinning is acceptable.

## Step 3: Rebuild native dylibs (if needed)

Per-platform rebuild scripts. `bazelisk clean --expunge` between rebuilds **only if** `patch_c_api.sh` / `WORKSPACE` patch changed (forces patch_cmds re-run on a fresh extraction). Otherwise incremental.

```bash
# macOS arm64
./native/litert_lm/build_macos.sh                # defaults to LATEST_TAG
# iOS device + simulator
./native/litert_lm/build_ios.sh                  # defaults to commit 5e0d86b — required for Metal
# Android arm64 (cross-compile from macOS)
./native/litert_lm/build_android.sh
# Linux x86_64 — on a Linux VM (use GCloud per project_gcloud_vm_workflow memory)
# Windows x86_64 — on a Windows VM (same)
```

Verify each rebuilt dylib:
```bash
nm -gU prebuilt/<os>_<arch>/libLiteRtLm.dylib | grep litert_lm_engine_create  # must export
otool -D prebuilt/<os>_<arch>/libLiteRtLm.dylib                              # @rpath/libLiteRtLm.dylib
```

If patches changed — also verify patch markers are baked into the binary, e.g.:
```bash
strings prebuilt/ios_arm64/libLiteRtLm.dylib | grep '@executable_path'
```

## Step 4: Pack tar.gz archives

Each archive is a flat tar of the matching `prebuilt/` directory. Naming: `litertlm-<os>_<arch>.tar.gz`.

```bash
DIST=$(mktemp -d)
for d in macos_arm64 ios_arm64 ios_sim_arm64 android_arm64 linux_x86_64 windows_x86_64; do
  if [ -d "native/litert_lm/prebuilt/$d" ]; then
    (cd "native/litert_lm/prebuilt/$d" && tar -czf "$DIST/litertlm-$d.tar.gz" .)
    echo "  $d: $(ls -la "$DIST/litertlm-$d.tar.gz" | awk '{print $5}') bytes"
  fi
done
```

Only archive platforms whose dylibs actually changed since the previous release. Untouched platforms keep their existing release assets.

## Step 5: Compute SHA256 + update hook/build.dart

```bash
for f in "$DIST"/litertlm-*.tar.gz; do
  printf "  '%s':\n      '%s',\n" "$(basename "$f")" "$(shasum -a 256 "$f" | awk '{print $1}')"
done
```

Paste each `<filename>: <sha256>` into the matching entry in `hook/build.dart` `_checksums` map. **Update only the platforms whose dylibs you actually rebuilt** — leave the others.

Also regenerate `checksums_litertlm.txt` for the GitHub Release page (single text file with `sha256  filename` lines):
```bash
(cd "$DIST" && shasum -a 256 litertlm-*.tar.gz > checksums_litertlm.txt)
```

## Step 6: Update GitHub Release assets

### Option A — overwrite existing tag (`native-v0.10.2`)
Use only if `_nativeVersion` did NOT bump. Replaces assets in place; downstream pinning to the tag will silently get new bytes.
```bash
RELEASE=native-v0.10.2
for f in "$DIST"/litertlm-*.tar.gz "$DIST"/checksums_litertlm.txt; do
  name=$(basename "$f")
  gh release delete-asset "$RELEASE" "$name" --yes 2>/dev/null || true
  gh release upload "$RELEASE" "$f"
done
```

### Option B — new tag (`native-v0.10.3`)
Cleanest. Old `native-v0.10.2` keeps working for old plugin versions. Need GitHub Release notes describing what changed.
```bash
RELEASE=native-v0.10.3
gh release create "$RELEASE" "$DIST"/litertlm-*.tar.gz "$DIST"/checksums_litertlm.txt \
  --title "Native dylibs $RELEASE" \
  --notes-file release-notes-native.md \
  --target main
```

Verify each URL returns HTTP 200 + sha256 matches:
```bash
for f in "$DIST"/litertlm-*.tar.gz; do
  name=$(basename "$f")
  url="https://github.com/DenisovAV/flutter_gemma/releases/download/$RELEASE/$name"
  curl -sI "$url" | head -1
  curl -sL "$url" | shasum -a 256 | awk '{print "  "$1"  '"$name"'"}'
done
```

## Step 7: Update CHANGELOG.md

Add new section at top. Categories: **App Store / packaging fixes**, **Features**, **Bug fixes**, **Breaking changes**, **Native runtime updates** (if `_nativeVersion` bumped). Reference issue / PR numbers (`#245`, `#239`).

### Style: terse, one line per item, mirror 0.13.x pattern

The user has rejected verbose CHANGELOG entries multiple times. Write each
bullet as **one short sentence** describing what was fixed and the
issue/PR reference. Do NOT explain root cause, history, build details,
or include workaround code blocks — that lives in commit messages and
issue threads, not in CHANGELOG.

Bad (rejected):
```
- **Fix Apple companion dylib min iOS** (#245): `libGemmaModelConstraintProvider.dylib`
  was built upstream with `minos 26.2`, causing App Store Connect to reject any
  app whose `Info.plist` minimum iOS is below 26.2. Patched to `minos 14.0` post-
  download (other companion dylibs already on 14.0/16.0). Filed upstream;
  permanent fix needs Google rebuild.
```

Good (matches 0.13.x):
```
- **Fix App Store ITMS-90208 rejection on iOS** (#245): downgraded patched
  `libGemmaModelConstraintProvider.dylib` minos 26.2 → 14.0 to match other
  companion dylibs.
```

Rule of thumb: each entry ≤ 2 lines wrapped at 100 cols. If you need more
to explain it, that's a sign it should be split into multiple entries
or moved to a separate doc.

## Step 8: Verify

```bash
flutter analyze
flutter test
dart pub publish --dry-run     # 0 warnings; check final package size <= 100 KB
```

**NEVER publish without dry-run first.** Publishing is IRREVERSIBLE.

## Step 9: Commit + tag + push

```bash
git add <changed files>
git commit -m "0.14.1: <one-line summary>" \
           --author="Sasha Denisov <denisov.shureg@gmail.com>"
# No "Co-Authored-By: Claude" / no AI attribution

git tag v0.14.1
git push origin <branch> --tags
```

## Step 10: pub.dev publish

```bash
dart pub publish --dry-run    # verify once more
dart pub publish              # only after user approval
```

## Step 11: Optional — GitHub plugin release

The `.github/workflows/release.yml` triggers on `v*.*.*` tag push and creates a GitHub Release with the example APK. Push the tag to fire it (already done in Step 9). Verify:
```bash
gh run list --workflow release.yml --limit 3
gh release view v0.14.1
```

## Common gotchas

- **`native/litert_lm/prebuilt/` excluded from pub package** (`.pubignore`) — end users get dylibs from GitHub Release, NOT from the pub package. Updating local prebuilts without re-uploading them is invisible to users.
- **iOS dylib must be built from commit `5e0d86b`** (post-v0.10.2). v0.10.2 tag predates `libLiteRtMetalAccelerator.dylib` → ABI mismatch → EXC_BAD_ACCESS in `litert_lm_engine_create` on iPhone GPU. `build_ios.sh` defaults to it; do not override unless you know what you're doing.
- **`bazelisk clean --expunge` is NOT free** — it forces a full rebuild (~25 min for one platform). Only do it when WORKSPACE patch_cmds changed; otherwise incremental rebuild.
- **Linux/Windows builds run on remote VMs** — see `project_gcloud_vm_workflow` memory.
- **macOS dylib produced LOCALLY**, not in CI — see `project_macos_dylib_built_locally` memory. Same for iOS.
- **Pub package size ceiling 100 KB** — `.pubignore` already excludes prebuilts, integration tests, and notebooks. If new top-level dirs creep in, dry-run will show > 100 KB and fail.
