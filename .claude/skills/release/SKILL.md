---
name: release
description: Release flutter_gemma — bump versions, optionally re-publish native prebuilts (iOS/macOS/Linux/Windows/Android dylibs) to GitHub Release, update SHA256 checksums in hook/build.dart, publish to pub.dev
user_invocable: true
---

# Flutter Gemma Release

Run as `/release <plugin-version>` (e.g. `/release 0.14.1`).

## Architecture context (read this first)

flutter_gemma 0.14.0+ has **no Kotlin/JVM/gRPC server**. Native libs come from one of two sources, decided per-platform by `hook/build.dart` (Native Assets):

1. **Local prebuilts** at `native/litert_lm/prebuilt/<os>_<arch>/` — populated locally by `native/litert_lm/build_*.sh` scripts. **NOT tracked in git** (gitignored since 0.14.3 — keeps clones lean) and **excluded from the pub package** via `.pubignore`. Maintainers regenerate them on demand and upload to a GitHub Release.
2. **GitHub Release `native-v<NATIVE_VERSION>` archives** (e.g. `native-v0.10.2-a`) — the **canonical source for both end users and CI**. URL pattern: `litertlm-<os>_<arch>.tar.gz` flat archive of the matching `prebuilt/` folder. End users fetch from there at `pub get` time via `hook/build.dart`. Maintainers re-fetch from there too if their local `prebuilt/` is missing (`gh release download native-v<X>` then extract — see Step 5).

Whether to bump `native-v<NATIVE_VERSION>` or re-publish the existing tag is the **central decision** of every release.

## Pre-flight

```bash
git status                  # all desired changes staged or already committed
git log --oneline -5
flutter analyze             # 0 errors
flutter test                # all pass

# Cross-platform compile sanity — analyze/test run on host VM and skip
# conditional imports (e.g. `lib/core/ffi/*_stub.dart`). The only thing
# that catches stub/client signature drift is `flutter build <target>`.
# Skipping this is how `enableSpeculativeDecoding` web breakage shipped
# in 0.15.0 — analyze was green, tests passed, web build threw
# `No named parameter ...` at dart2js time.
#
# Android MUST be built --release, not --debug: a release build runs R8
# (shrink/minify/obfuscate) and the full native-asset packaging path, which
# debug skips. Bugs that only surface under R8 (stripped classes, missing
# keep rules, native lib packaging) are invisible to `--debug`.
cd example
flutter build web --no-tree-shake-icons
flutter build apk --release
flutter build macos --debug
flutter build ios --no-codesign --debug
cd ..
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

### ⛔ NEVER overwrite a tag referenced by a published plugin version

`gh release upload --clobber` on an existing `native-v*` / `qdrant-edge-v*`
tag silently breaks every end user already on a plugin version whose
`hook/build.dart` references that tag. The published SHA256 (in their
`pubspec.lock`-pinned plugin code) no longer matches the bytes GitHub
serves, the hook deletes the archive and returns null, the build
succeeds with a missing CodeAsset, and the app crashes at runtime on
first `dlopen()`.

This is unrecoverable. `tar -czf` is not deterministic across runs
(mtime, file ordering, gzip block boundaries differ), so even with
every original dylib byte you cannot reproduce the original tar SHA256.

**Always publish a new tag instead** — `native-v0.10.3`, not
`native-v0.10.2` reuploaded. The cost of a new tag is zero; the cost
of breaking a shipped plugin version is real users with runtime
crashes who cannot upgrade until the next release cycle.

See `feedback_never_reupload_released_tarballs.md` for the full
incident write-up.

### Always: new tag (`native-v0.10.3`)
Old `native-v0.10.2` keeps working for old plugin versions. Need
GitHub Release notes describing what changed.
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

### ⛔ Three-way checksum consistency — MANDATORY (regression: #316)

`checksums_litertlm.txt` is informational (the build hook does NOT read it —
it verifies against the `_checksums` map baked into `hook/build.dart`). But a
STALE txt is dangerous: in #316 a user (`@remingtonc`) hand-verified against
the txt during a checksum-mismatch debug, the txt said `e24804d9…` while the
actual asset was `f809c5a2…`, and it sent them down the wrong path. **For
every tag you touch, the same SHA must appear in all THREE places** —
the uploaded `.tar.gz`, `checksums_litertlm.txt` on the Release, and the
`hook/build.dart` `_checksums` entry. Verify after upload:

```bash
for f in "$DIST"/litertlm-*.tar.gz; do
  name=$(basename "$f")
  # 1. actual asset bytes served by GitHub
  asset=$(curl -sL "https://github.com/DenisovAV/flutter_gemma/releases/download/$RELEASE/$name" | shasum -a 256 | awk '{print $1}')
  # 2. what checksums_litertlm.txt on the Release claims
  txt=$(curl -sL "https://github.com/DenisovAV/flutter_gemma/releases/download/$RELEASE/checksums_litertlm.txt" | awk -v n="$name" '$2==n{print $1}')
  # 3. what hook/build.dart expects
  hook=$(grep -A1 "'$name'" hook/build.dart | grep -oE "[0-9a-f]{64}" | head -1)
  echo "$name:"
  echo "  asset=$asset"
  echo "  txt  =$txt   $([ "$asset" = "$txt" ] && echo OK || echo '❌ STALE TXT')"
  echo "  hook =$hook   $([ "$asset" = "$hook" ] && echo OK || echo '❌ HOOK MISMATCH — users will fail to build')"
done
```
All three must match for every platform you re-uploaded. If you re-uploaded a
`.tar.gz` you MUST also re-upload a fresh `checksums_litertlm.txt` in the same
`gh release upload --clobber` — never one without the other.

(See also the ⛔ "NEVER overwrite a tag referenced by a published plugin
version" rule in Step 6 — #316 is what a stale released tag looks like in the
wild.)

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
# Cross-platform compile sanity (also in Pre-flight — rerun here after
# version bumps in case a setter/getter signature shifted):
(cd example && flutter build web --no-tree-shake-icons)
(cd example && flutter build apk --release)   # --release, not --debug: exercises R8 + native packaging
(cd example && flutter build macos --debug)
(cd example && flutter build ios --no-codesign --debug)
dart pub publish --dry-run     # 0 warnings (package size is informational — the
                               # FFI bindings + pigeon + example already push it
                               # to ~700 KB on 0.16.x; the old <=100 KB ceiling
                               # predates 0.14.0 and no longer applies)
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

- **iOS dylib `minos` MUST equal the Flutter wrapper plist (13.0) — for EVERY native bundle, not just LiteRT-LM.** Flutter Native Assets hardcodes `MinimumOSVersion 13.0` into each generated `*.framework/Info.plist`; if a bundled dylib's binary `minos` is higher, App Store Connect rejects the archive with **ITMS-90208**. Both `litert_lm/build_ios.sh` and `qdrant_edge/build_local.sh` normalize to 13.0 via `vtool -set-build-version <ios|iossim> 13.0 18.5`. **After building ANY iOS dylib (current or a future new artifact), verify:** `vtool -show <dylib> | grep minos` → must be `13.0`. The real iOS 16+ floor is enforced by the podspec, not this metadata. Regressed in 0.16.3 when qdrant un-vendoring shipped a 16.0 dylib (#286) — the check was only in the LiteRT-LM script, not a release-wide rule.
- **`native/litert_lm/prebuilt/` excluded from pub package** (`.pubignore`) — end users get dylibs from GitHub Release, NOT from the pub package. Updating local prebuilts without re-uploading them is invisible to users.
- **iOS dylib must be built from commit `5e0d86b`** (post-v0.10.2). v0.10.2 tag predates `libLiteRtMetalAccelerator.dylib` → ABI mismatch → EXC_BAD_ACCESS in `litert_lm_engine_create` on iPhone GPU. `build_ios.sh` defaults to it; do not override unless you know what you're doing.
- **`bazelisk clean --expunge` is NOT free** — it forces a full rebuild (~25 min for one platform). Only do it when WORKSPACE patch_cmds changed; otherwise incremental rebuild.
- **Linux/Windows builds run on remote VMs** — see `project_gcloud_vm_workflow` memory.
- **macOS dylib produced LOCALLY**, not in CI — see `project_macos_dylib_built_locally` memory. Same for iOS.
- **Pub package size ceiling 100 KB** — `.pubignore` already excludes prebuilts, integration tests, and notebooks. If new top-level dirs creep in, dry-run will show > 100 KB and fail.
