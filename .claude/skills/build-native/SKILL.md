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

iOS dylib **must** be built from upstream LiteRT-LM commit **`5e0d86b`** ("Update dependencies of litert_lm"). It is the first commit that ships `libLiteRtMetalAccelerator.dylib` for iOS. The `v0.10.2` tag predates this — building against it produces a `libLiteRtLm.dylib` whose Metal accelerator vtable doesn't match the prebuilt framework, and you get `EXC_BAD_ACCESS` inside `litert_lm_engine_create` on iPhone. `build_ios.sh` already defaults to `5e0d86b`. Do not pass `v0.10.2`.

macOS, Linux, Windows, Android: latest tag (currently `v0.10.2`) works — the Metal accelerator constraint is iOS-only.

### Required linker flags

| Platform | Flag | Why |
|---|---|---|
| **macOS / iOS** | `-Wl,-headerpad_max_install_names` | Native Assets re-runs `install_name_tool -id @rpath/...` on every `pub get`. Without headerpad, the rewrite fails with "larger updated load commands do not fit" and `pub get` aborts. |
| Linux | `-Wl,--dynamic-list=...` (already in patch_c_api.sh §1) | Exports LiteRt* / litert_lm_* symbols for the WebGPU accelerator's `dlsym(RTLD_DEFAULT)` |
| Windows | `/DEF:windows_exports.def` (already in patch_c_api.sh §1) | Bazel native attribute |
| All | `-fvisibility=hidden` is **WRONG** for our use case — needs default visibility on the listed export sets |

The `headerpad_max_install_names` flag is **not optional on Apple platforms**. Verify in the post-build checklist below.

### Patches we apply

`native/litert_lm/patch_c_api.sh` sections:
1. `cc_binary(linkshared=True)` target + Linux dynamic-list + Windows .def
2-3. `set_max_num_images` C API + `set_cache_dir` propagation to vision/audio executors
4. `set_litert_dispatch_lib_dir` C API
5. 6-arg `litert_lm_conversation_config_create` overload
6-9. `SetPendingSamplerParams` virtual + executor override + `SessionBasic` push (matches our PR #2081 — drop these once it merges)
10b. **App Store ITMS-90432 fix** — rewrite `gpu_registry.cc` dlopen to `@executable_path/...framework/<X>` path on Apple. **iOS-critical** — without it App Store rejects 0.14.0 builds.

§10a (sampler_factory.cc) is **deliberately NOT patched** — `libLiteRtTopKMetalSampler.dylib` has 3-of-7 broken exports on Apple (#2073). Patching it surfaces a NULL-vtable crash. Leave the basename dlopen so `sampler_factory.cc` falls back to CPU sampler. Revisit when Google fixes #2073.

---

## Build commands

```bash
# macOS arm64 (run on a Mac)
./native/litert_lm/build_macos.sh             # latest tag is fine

# iOS device + simulator (run on a Mac)
./native/litert_lm/build_ios.sh               # defaults to 5e0d86b — DO NOT override

# Android arm64 (cross-compile from macOS)
./native/litert_lm/build_android.sh

# Linux x86_64  → flutter-gemma-linux GCloud VM
# Windows x86_64 → flutter-gemma-gpu GCloud VM (long-running, use Scheduled Task)
# See project_gcloud_vm_workflow memory.
```

**`bazelisk clean --expunge` before rebuild only if WORKSPACE patch_cmds changed** (otherwise incremental is fine and ~5× faster).

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

### 2. Header padding (macOS / iOS) — **the one I missed**

```bash
otool -h native/litert_lm/prebuilt/<dir>/libLiteRtLm.dylib | tail -1 | awk '{print $7}'
# → sizeofcmds. Need >= 4096 to safely rewrite install_name later.
```

If `sizeofcmds < 4096`, the dylib was built without `-headerpad_max_install_names`. Native Assets will fail every `pub get` on macOS with:

> `install_name_tool: changing install names or rpaths can't be redone for: ... larger updated load commands do not fit`

**This is what bit users in 0.14.1 #247.** No way to retroactively add headerpad to an already-linked binary — you must rebuild.

For dylibs we don't build ourselves (upstream prebuilts like `libGemmaModelConstraintProvider.dylib`, `libLiteRtMetalAccelerator.dylib`, `libLiteRtTopKMetalSampler.dylib`): file an upstream bug, then either rebuild from source with the flag, or use `optool` / `ld -r` to relink with bigger headerpad.

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

Every one of those would have been caught by checks 1-8 before commit. **Run them all every time.**

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
