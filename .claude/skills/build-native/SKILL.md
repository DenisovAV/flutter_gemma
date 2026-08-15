---
name: build-native
description: Rebuild native LiteRT-LM prebuilts for flutter_gemma (iOS / macOS / Linux / Windows / Android) — covers required build flags, the upstream commit pin, and a mandatory post-build verification checklist that catches the bugs we have already shipped at users.
user_invocable: true
---

# Build native dylibs for flutter_gemma — the right way

This skill exists because we shipped 0.14.0 and 0.14.1 with native dylibs that broke real users (App Store rejection in 0.14.0, `install_name_tool` headerpad failure in 0.14.1, x86_64-not-arm64 in upstream prebuilts). Every one of those was caught **after** publish. The verification checklist below would have caught all of them locally.

**Read top to bottom before rebuilding anything.** The checklist is non-optional.

---

## Pre-build setup

### Required upstream commit

**Pin the exact tag commit SHA on every platform, and pass it explicitly.** Upstream has retagged releases in place before, so a tag *name* is not a stable reference. Get the SHA with:

```bash
gh api repos/google-ai-edge/LiteRT-LM/git/ref/tags/<tag> --jq '.object.sha'
```

The scripts' `DEFAULT_REF` lags whatever release you are migrating to, so never rely on it — `build_ios.sh` still defaulted to the v0.14.0-era `80f301ff` during the v0.15.0 migration.

**The historical iOS `5e0d86b` pin is obsolete.** It existed because `5e0d86b` was the first commit shipping `libLiteRtMetalAccelerator.dylib` for iOS, and older tags produced a `libLiteRtLm.dylib` whose Metal-accelerator vtable didn't match the prebuilt framework → `EXC_BAD_ACCESS` inside `litert_lm_engine_create` on device. Modern tags ship their own `prebuilt/ios_arm64/`, so building iOS from the tag is now the *safer* option.

The real invariant is: **source and accelerator prebuilts must come from the same tree.** Mixing them is the hazard — not the choice of tag. Verify before building:

```bash
gh api "repos/google-ai-edge/LiteRT-LM/contents/prebuilt/ios_arm64?ref=<tag>" --jq '.[].name'
# needs libLiteRtMetalAccelerator.dylib + libLiteRtTopKMetalSampler.dylib
```

### The LiteRT pin is a second ABI surface — check it every time

A LiteRT-LM bump silently moves `LITERT_REF` in `WORKSPACE` (line ~6), and that is a **different upstream repo** with its own C API. This matters because the packages consume two different APIs:

- `flutter_gemma_litertlm` → LiteRT-LM C API (`c/engine.h`)
- `flutter_gemma_embeddings`, `flutter_gemma_speech` → **LiteRT** C API directly, via hand-written bindings in `lib/src/litert/`

So a green litertlm smoke run proves nothing about embeddings. In the v0.14.0 migration the pin moved, `LiteRtCreateModelFromFile` gained a third parameter (`LiteRtEnvironment` first), and embeddings silently returned `status=500` — a full day lost before the cause was found.

```bash
for t in <old-tag> <new-tag>; do
  gh api "repos/google-ai-edge/LiteRT-LM/contents/WORKSPACE?ref=$t" --jq '.content' | base64 -d | grep '^LITERT_REF'
done
```

If it moved, diff the headers the bindings use (`litert/c/litert_{model,environment,options,tensor_buffer,compiled_model}.h`) at both refs. Symbol list:
`grep -ohE "LiteRt[A-Za-z_]+" packages/flutter_gemma_embeddings/lib/src/litert/*.dart | sort -u`

Known: v0.14.0 (`622f1f3c`) **breaking**; v0.15.0 (`3cb830ad`) safe — four headers byte-identical, `litert_compiled_model.h` only gains `LiteRtGetCompiledModelEnvironment()`.

### Required linker flags

| Platform | Flag | Why |
|---|---|---|
| **macOS / iOS** | `-Wl,-headerpad_max_install_names` | Native Assets re-runs `install_name_tool -id @rpath/...` on every `pub get`. Without headerpad, the rewrite fails with "larger updated load commands do not fit" and `pub get` aborts. |
| **macOS** | `-mmacosx-version-min=11.0` | Without it clang stamps `LC_BUILD_VERSION` with the **build host's** OS, so the bundle's floor silently tracks whichever Mac produced it. |
| **Android** | `aarch64-linux-android24-clang` (target triple carries the API level) | Same reason, stated explicitly rather than inherited. |
| Linux | `-Wl,--dynamic-list=...` (already in patch_c_api.sh §1) | Exports LiteRt* / litert_lm_* symbols for the WebGPU accelerator's `dlsym(RTLD_DEFAULT)` |
| Windows | `/DEF:windows_exports.def` (already in patch_c_api.sh §1) | Bazel native attribute |
| All | `-fvisibility=hidden` is **WRONG** for our use case — needs default visibility on the listed export sets |

The `headerpad_max_install_names` flag is **not optional on Apple platforms**. Verify in the post-build checklist below.

**Deployment target must be stated, never inherited.** This bites only the libraries *we* compile — the upstream prebuilt companions arrive with their own sane values (11.0 / 14.0), so a single odd number in the middle of an otherwise healthy bundle is the signature. `native-v0.14.0` shipped `libStreamProxy.dylib` with `minos 26.0` for exactly this reason: `build_macos.sh` compiled it with a bare `clang -shared` on a macOS 26 host, while `example/macos/Podfile` advertises `platform :osx, '10.15'`. `build_ios.sh` never had the bug because its step 8b force-normalizes every companion to 13.0 with `vtool -set-build-version`. Check every self-built binary:

```bash
for f in prebuilt/macos_arm64/*.dylib; do
  printf "%-46s minos=%s\n" "$(basename $f)" "$(vtool -show-build "$f" | awk '/minos/{print $2; exit}')"
done
```

Anything at or near the current macOS release means the flag was dropped. Rebuilding one dylib is a two-second `clang` call — no Bazel involved — so there is never a reason to ship it wrong.

### Patches we apply

`native/litert_lm/patch_c_api.sh` — the surviving sections (2–9 were **deleted** at the v0.14.0 migration once upstream implemented them natively; don't go looking for them):

1. `cc_binary(linkshared=True)` target + Linux dynamic-list + Windows .def
4b. `set_use_hw_masking_for_npu` (Intel LunarLake/PantherLake — default `true` crashes their NPU)
4c. GPU smooth-UI knobs — `gpu_context_low_priority` + `kernel_batch_size` (#364)
10b. **App Store ITMS-90432 fix** — rewrite `gpu_registry.cc` dlopen to `@executable_path/...framework/<X>` on Apple. **iOS-critical.**
11. minizip/zlib mirrored off the flaky zlib.net

§10a (sampler_factory.cc) is **deliberately NOT patched** — `libLiteRtTopKMetalSampler.dylib` has 3-of-7 broken exports on Apple (#2073). Patching it surfaces a NULL-vtable crash. Leave the basename dlopen so `sampler_factory.cc` falls back to CPU sampler. Revisit when Google fixes #2073.

Dry-run the patcher against the new tag before building anything — every section must print `OK`, never `WARN`:

```bash
bash native/litert_lm/patch_c_api.sh /tmp/LiteRT-LM
```

On Windows/git-bash, `python3` resolves to the Microsoft Store stub, which prints "Python was not found" **and still exits 0** — so sections 10b and 11 silently no-op. Shim it first:
`printf '#!/bin/sh\nexec "<path>/python.exe" "$@"\n' > /somewhere/python3 && chmod +x` and prepend that dir to `PATH`.

### Cloning upstream without fighting the network

The repo carries large LFS binaries; a full clone repeatedly dies mid-transfer on anything but a rock-solid link, and the failure restarts from zero. Clone the tag shallow with LFS deferred, then pull only the platforms you're building:

```bash
GIT_LFS_SKIP_SMUDGE=1 git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 \
  clone --depth 1 --branch <tag> https://github.com/google-ai-edge/LiteRT-LM /tmp/LiteRT-LM
cd /tmp/LiteRT-LM
git lfs pull --include="prebuilt/macos_arm64/*,prebuilt/ios_arm64/*,prebuilt/ios_sim_arm64/*,prebuilt/android_arm64/*"
```

**Then point `origin` at a local bare mirror.** `build_*.sh` run `git fetch --tags --force origin` whenever the clone dir already exists — cheap on a full clone, near-endless on a shallow one, because every other tag's objects have to be fetched. Redirecting origin makes that fetch local and instant (measured: 0.03 s), and removes the network from the build loop entirely:

```bash
git clone --bare /tmp/LiteRT-LM /tmp/LiteRT-LM-mirror.git
cd /tmp/LiteRT-LM && git remote set-url origin /tmp/LiteRT-LM-mirror.git
```

Verify the LFS pull produced real binaries, not pointers — `head -c 20 <file>` starting with `version https` means it's still a pointer.

### ⚠️ NPU stacks are NOT produced by the build — carry them forward

Both NPU dispatch stacks live in the previous release, not in the compiler output. A fresh build always yields **zero** of them; treat that as the default, not as a failure to investigate. Confirmed at v0.14.0 ("2 critical NPU drops") and again at v0.15.0.

| Bundle | Files to restore | Pattern |
|---|---|---|
| `windows_x86_64` | **12** — Intel NPU dispatch | `LiteRtDispatch.dll`, `openvino*.dll`, `tbb*.dll` |
| `android_arm64` | **11** — Qualcomm QNN | `libQnn*.so`, `libLiteRtDispatch_Qualcomm.so` |

```bash
gh release download native-v<prev> --repo DenisovAV/flutter_gemma \
  -p "litertlm-windows_x86_64.tar.gz" -D /tmp/prev --clobber
mkdir -p /tmp/prev/x && tar xzf /tmp/prev/litertlm-windows_x86_64.tar.gz -C /tmp/prev/x
find /tmp/prev/x -maxdepth 1 -type f \( -name 'LiteRtDispatch*' -o -name 'openvino*' -o -name 'tbb*' \) \
  -exec cp -p {} <windows-bundle-dir>/ \;
```

Then assert both the count **and** byte-identity against the previous release (sha256 per file). Shipping without them doesn't fail any build — it fails silently for every user on `PreferredBackend.npu`.

---

## Build commands

Always pass the pinned SHA explicitly — the scripts' `DEFAULT_REF` lags the release you're migrating to.

```bash
REF=<tag-commit-sha>
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/29.0.14206865"   # r29 mandatory

./native/litert_lm/build_macos.sh   "$REF"    # macOS arm64
./native/litert_lm/build_ios.sh     "$REF"    # iOS device + simulator
./native/litert_lm/build_android.sh "$REF"    # Android arm64, cross-compiled
```

`ANDROID_NDK_HOME` must be **exported explicitly**: `build_android.sh` auto-detects the newest NDK *only when the variable is unset*, so a stale value in your shell silently selects the wrong toolchain (r26 fails on a C++20 concept in the minijinja chat template).

**Linux x86_64/arm64 and Windows x86_64 build in CI**, not on a VM: dispatch `build-litertlm-native.yml` with `-f litertlm_version=<SHA>`. Use `--ref <branch>` if the migration carries source changes — the workflow compiles `stream_proxy.c` from the checked-out tree, so dispatching from `main` would silently ship a stale shim.

**`bazelisk clean --expunge` before rebuild only if WORKSPACE patch_cmds changed** (otherwise incremental is fine and ~5× faster — a warm cache can finish a platform in 2–5 min, which is normal and not a sign that nothing was built).

### Never trust a build's exit code — verify artifacts

Wrapper scripts have reported success while producing nothing (a failed `git clone` inside the script, an `echo` after the build masking its status, `gh` printing a network error and still exiting 0). Confirm each platform by **artifact**, not by status line:

```bash
f=prebuilt/<dir>/libLiteRtLm.dylib      # or .so
printf "exists=%s mtime=%s newversion_symbol=%s\n" \
  "$([ -f "$f" ] && echo yes || echo NO)" \
  "$(stat -f '%Sm' -t '%H:%M' "$f" 2>/dev/null)" \
  "$([ -f "$f" ] && nm -gU "$f" 2>/dev/null | grep -c '<symbol-new-in-this-version>')"
```

Print `exists` **next to** the symbol count. `nm` on a missing file emits nothing and `grep -c` turns that into a perfectly innocent `0` — "feature absent" and "check never ran" must not look identical. The same applies to shell globs: in zsh an unmatched `*.so` aborts the whole `ls`, so use `find … \( -name '*.dylib' -o -name '*.so' \)` in verification loops.

---

## ⚠️ Post-build verification — MANDATORY before pushing prebuilts to repo

Every freshly-built dylib must pass **all** of these checks. Skipping any one of them has shipped a regression to users.

### 1. Mach-O architecture (iOS / macOS / desktop)

```bash
file native/litert_lm/prebuilt/<dir>/libLiteRtLm.dylib
```

Expected: `arm64` for iOS device, `arm64` for iOS Sim, `arm64` for macOS_arm64. **Not x86_64.** Upstream `5e0d86b` shipped `libLiteRt.dylib` and `libLiteRtTopKMetalSampler.dylib` as **x86_64 macOS binaries inside `prebuilt/ios_arm64/`** (#2072) — when you copy them across, double-check.

```bash
otool -hv native/litert_lm/prebuilt/<dir>/libLiteRtLm.dylib | tail -2
# → cputype 16777228 (arm64), filetype 6 (DYLIB)
```

### 2. Header padding (macOS / iOS) — measure it with check #4, not with `sizeofcmds`

Native Assets re-runs `install_name_tool -id @rpath/...` on every `pub get`. Without enough header padding the rewrite fails with:

> `install_name_tool: changing install names or rpaths can't be redone for: ... larger updated load commands do not fit`

**This is what bit users in 0.14.1 (#247).** Padding cannot be added to an already-linked binary — you must rebuild with `-Wl,-headerpad_max_install_names`.

**Do not test this by comparing `sizeofcmds` against a threshold.** An earlier version of this skill said "need `sizeofcmds >= 4096`", which is wrong: `sizeofcmds` is the *current* size of the load commands, while `-headerpad_max_install_names` enlarges the *free space* after them. A small library legitimately has small load commands — `libStreamProxy.dylib` reports ~1136 and rewrites perfectly. At the v0.15.0 migration that threshold flagged 8 healthy dylibs, including three upstream ones, and would have blocked the release for nothing.

**Check #4 below is the only authoritative test** — it performs the exact operation Native Assets performs. Run it over every dylib in the directory and trust its result.

For dylibs we don't build ourselves (upstream prebuilts like `libGemmaModelConstraintProvider.dylib`, `libLiteRtMetalAccelerator.dylib`, `libLiteRtTopKMetalSampler.dylib`) that genuinely fail check #4: file an upstream bug, then either rebuild from source with the flag, or relink with `optool` / `ld -r` for bigger headerpad.

### 3. install_name + rpath

```bash
otool -D <file>  # → @rpath/libLiteRtLm.dylib (NOT absolute path)
otool -l <file> | grep -A2 LC_RPATH | grep " path "
# Expected for macOS: @loader_path/../../..
# Expected for iOS:   @loader_path or @executable_path/Frameworks/...
```

### 4. install_name_tool smoke test

The mandatory test that catches headerpad bugs:

```bash
cp native/litert_lm/prebuilt/<dir>/libX.dylib /tmp/test.dylib
chmod +w /tmp/test.dylib
install_name_tool -id @rpath/this_is_a_long_test_path_pad_to_native_assets_target/libX.dylib /tmp/test.dylib
# → must succeed silently. If it fails with "larger updated load commands do not fit", headerpad is too small. STOP and rebuild.
```

Run this for **every** dylib in `prebuilt/<dir>/`, not just the one you rebuilt. Native Assets rewrites all of them.

### 5. Phase 8 patch markers (iOS / macOS only)

```bash
strings native/litert_lm/prebuilt/<dir>/libLiteRtLm.dylib | grep '@executable_path.*LiteRtMetalAccelerator'
```

Expected: 1 hit (path to `LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator`). If 0 hits, `patch_c_api.sh` §10b didn't apply — your build was against a tree where `WORKSPACE.patch_cmds` didn't run. Run `bazelisk clean --expunge` and rebuild.

```bash
strings native/litert_lm/prebuilt/<dir>/libLiteRtLm.dylib | grep -c '^libLiteRtMetalAccelerator.dylib$'
```

Expected: 0. If non-zero, the basename dlopen string is still in the binary — patch failed.

### 6. Required exports

```bash
nm -gU native/litert_lm/prebuilt/<dir>/libLiteRtLm.dylib | grep _litert_lm_engine_create
# → must show the symbol as T (text section, exported)
```

Run `nm -gU | grep -c '_litert_lm_'` — expect ~50 symbols (matches `bindings.dart` lookupFunction count).

### 7. **Real `pub get` smoke test in a fresh project**

This catches problems no static check sees. Mandatory before commit:

```bash
cd /tmp
rm -rf test_flutter_gemma_native
flutter create test_flutter_gemma_native --platforms=macos,ios
cd test_flutter_gemma_native
flutter pub add flutter_gemma --path=/Users/sashadenisov/Work/flutter_gemma
rm -rf .dart_tool build
flutter pub get
# → must complete without "Failed to set install names" or any other error
flutter build macos --debug    # mandatory
flutter build ios --debug --no-codesign   # mandatory (catches dylib loading)
```

**This is the smoke test I skipped in 0.14.1.** Doing this once would have caught the `libGemmaModelConstraintProvider.dylib` headerpad issue before publish.

### 8. (App Store-bound builds) Frameworks/ structural check

After `flutter build ipa --release` or archive:

```bash
ls Runner.app/Frameworks/
# → only *.framework directories. Zero loose .dylib files. Zero symlinks.
find Runner.app/Frameworks/ -maxdepth 1 -type l   # must be empty
find Runner.app/Frameworks/ -maxdepth 1 -name "*.dylib" -type f   # must be empty
```

If anything other than `.framework/` is in there, App Store will reject with ITMS-90432 ("Unexpected file found in Frameworks").

---

## Common pitfalls (regressions we already shipped)

| # | Bug | Caught by | Hit users in |
|---|---|---|---|
| 1 | iOS dylib built from `v0.10.2` (no Metal accelerator), EXC_BAD_ACCESS | Check #5 (patch markers absent) + iPhone smoke | dev session, never shipped |
| 2 | App Store ITMS-90432 — `lib*.dylib` symlinks in Frameworks/ | Check #8 | **0.14.0** |
| 3 | `dart:ffi` in web build — missing conditional import | `flutter build web --release` | **0.14.0** |
| 4 | `libGemmaModelConstraintProvider.dylib` headerpad too small | Check #2 + #4 + #7 | **0.14.1** |
| 5 | `lipo` "same architectures (arm64)" — Native Assets called twice for iOS | hook/build.dart `_prebuiltDirName` returns null for iOS x64 | dev session |
| 6 | upstream `libLiteRt.dylib` was x86_64 macOS binary in `prebuilt/ios_arm64/` (#2072) | Check #1 (`file`) | 5e0d86b commit (upstream bug, but we should detect on copy) |
| 7 | NPU dispatch stacks dropped from the tarballs — build never emits them | Count + sha256 vs previous release | **caught pre-publish** at v0.14.0 *and* v0.15.0 |
| 8 | LiteRT pin moved, `LiteRtCreateModelFromFile` 2→3 args → embeddings `status=500` | Header diff at both `LITERT_REF`s | v0.14.0 dev cycle, ~1 day lost |
| 9 | `RTLD_DEFAULT` undeclared on glibc — needs `_GNU_SOURCE` before every include | CI Linux job (macOS compiles it happily) | **caught in CI** at v0.15.0 |
| 10 | v0.15.0 changed `LiteRtLmStreamCallback` 4-arg → 2-arg, no compat overload | ACCESS_VIOLATION (Windows) / malformed UTF-8 (macOS) at first token | **caught pre-publish** at v0.15.0 |

Every one of those would have been caught by checks 1-8 before commit. **Run them all every time.**

Two of these deserve emphasis because nothing in the build output hints at them:

- **#7 is silent.** The tarball packs, the checksums verify, every smoke test on CPU/GPU passes. Only a user with `PreferredBackend.npu` finds out.
- **#8 and #10 are ABI drift, not code changes on our side.** C linkage means a stale call shape still links; you get register garbage instead of a compiler error. When a bump touches any callback or C-API signature, verify the shape at both refs rather than assuming source that compiles is source that's correct.

---

## When upstream is broken

We import some dylibs as-is from upstream LiteRT-LM (`libGemmaModelConstraintProvider.dylib`, `libLiteRtMetalAccelerator.dylib`, sampler dylibs). When upstream ships them with insufficient headerpad / wrong arch / broken exports:

1. **File an issue with reproducer** — see `project_litertlm_upstream_*` memories for our open ones (#1990, #2072, #2073, #2080).
2. **Don't ship them blindly.** Run check #4 (install_name_tool smoke) on every upstream-sourced dylib **before** copying to `prebuilt/`. If it fails, **don't publish** — find a workaround first (relink, or ship without that lib + change Dart code path).
3. **Add a memory entry** documenting the bug + workaround in `~/.claude/projects/.../memory/project_*.md` so future sessions don't re-discover it.

---

## After successful build

1. **Run the verification checklist 1-8 above. All checks must pass.**
2. Commit the new dylibs (`git add prebuilt/<dir>/*.dylib`)
3. Pack tarballs + update `hook/build.dart` `_checksums` + re-upload to GitHub Release `native-v<version>` (see `release` skill).
4. Run `dart pub publish --dry-run` — must show 0 warnings.
5. Only then publish.
