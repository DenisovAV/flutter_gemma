---
name: build-native
description: Rebuild native LiteRT-LM prebuilts for flutter_gemma (iOS / macOS / Linux / Windows / Android) — covers required build flags, the upstream commit pin, and a mandatory post-build verification checklist that catches the bugs we have already shipped at users.
user_invocable: true
---

# Build native dylibs for flutter_gemma — the right way

This skill exists because we shipped 0.14.0 and 0.14.1 with native dylibs that broke real users (App Store rejection in 0.14.0, `install_name_tool` headerpad failure in 0.14.1, x86_64-not-arm64 in upstream prebuilts). Every one of those was caught **after** publish. The verification checklist below would have caught all of them locally.

The v0.16.0 migration added a second class of defect, and it is the more expensive one: **inputs we pinned once and stopped maintaining** — a Bazel define upstream had deleted, an OpenVino SDK four minor versions behind the pin, a dispatch library hardcoded to a LiteRT commit from four releases ago. None of them fails a build. All of them fail at a version boundary, which makes them look exactly like upstream regressions — and we filed two upstream issues that had to be retracted before finding that out.

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

A LiteRT-LM bump silently moves `LITERT_REF` in `WORKSPACE` (line ~6), and that is a **different upstream repo** with its own C API. This matters because three separate things bind to it:

- `flutter_gemma_litertlm` → LiteRT-LM C API (`c/engine.h`)
- `flutter_gemma_embeddings`, `flutter_gemma_speech` → **LiteRT** C API directly, via hand-written bindings in `lib/src/litert/`
- **both NPU dispatch libraries** → the `LiteRtDispatchApi` struct and the LiteRT runtime they are loaded into

So a green litertlm smoke run proves nothing about embeddings, and nothing at all about NPU. In the v0.14.0 migration the pin moved, `LiteRtCreateModelFromFile` gained a third parameter (`LiteRtEnvironment` first), and embeddings silently returned `status=500` — a full day lost before the cause was found.

```bash
for t in <old-tag> <new-tag>; do
  gh api "repos/google-ai-edge/LiteRT-LM/contents/WORKSPACE?ref=$t" --jq '.content' | base64 -d | grep '^LITERT_REF'
done
```

If it moved, diff the headers the bindings use (`litert/c/litert_{model,environment,options,tensor_buffer,compiled_model}.h`) at both refs. Symbol list:
`grep -ohE "LiteRt[A-Za-z_]+" packages/flutter_gemma_embeddings/lib/src/litert/*.dart | sort -u`

Known pins: v0.14.0 → `622f1f3c` (**breaking** for embeddings); v0.15.0 → `3cb830ad` (safe — four headers byte-identical, `litert_compiled_model.h` only gains `LiteRtGetCompiledModelEnvironment()`); v0.16.0 → `0ff28117f1cb5556d0e015bf80b773f74e2bee51`.

**Never hardcode this ref in a build script.** `build_qualcomm_dispatch.sh` carried a literal `5c5b9ce6` from the native-v0.12.0 era and nobody noticed for four releases, because a stale dispatch library does not fail politely — see the NPU section below. Derive it from the WORKSPACE of the LiteRT-LM revision being built:

```bash
LITERT_REF="$(curl -fsSL \
  "https://raw.githubusercontent.com/google-ai-edge/LiteRT-LM/$LITERTLM_REF/WORKSPACE" \
  | sed -n 's/^LITERT_REF *= *"\([0-9a-f]*\)".*/\1/p' | head -1)"
[ -n "$LITERT_REF" ] || { echo "could not resolve LITERT_REF" >&2; exit 1; }
```

The empty-result guard matters: `curl | sed` on a moved/renamed WORKSPACE yields an empty string, and an empty `--define` or checkout ref fails much later and much less legibly than an explicit `exit 1` here.

### Bazel defines rot — confirm each one still exists in the tree

A `--define` that upstream has deleted is **not an error**. Bazel accepts any `--define=key=value`; if no `config_setting` reads that key, the flag is silently inert and you get the default build.

We passed `--define=litert_link_capi_so=true` on Windows and Linux for three releases. Upstream removed the name; it has **zero occurrences** in the v0.16.0 tree. The live name is `litert_runtime_link_mode=dynamic`. This was harmless until v0.14.0 split Dawn out of the WebGPU accelerator, from which point the statically-linked runtime is exactly what crashed GPU `engine_create` — reported upstream as #2957 and **retracted**, because the cause was ours.

Before trusting any define in a build command, grep the tree you are about to build:

```bash
for d in litert_runtime_link_mode resolve_symbols_in_exec <any-other>; do
  printf "%-32s %s\n" "$d" "$(grep -rl "$d" /tmp/LiteRT-LM --include='*.bzl' --include='BUILD*' --include='*.bazelrc' 2>/dev/null | wc -l)"
done
```

Zero files means the flag is dead — find the replacement in `docs/getting-started/build-and-run.md`, do not leave it in "just in case". Both of the current desktop defines are documented there as **mandatory for GPU**:

| Define | Why |
|---|---|
| `litert_runtime_link_mode=dynamic` | Keeps the LiteRt C API **out** of `libLiteRtLm` so it resolves against the separately shipped `libLiteRt` at runtime — which is what the prebuilt WebGPU accelerator and the split `libwebgpu_dawn` expect. |
| `resolve_symbols_in_exec=false` | Without it Bazel cannot resolve `LiteRt*` imports at link time (167 unresolved externals). |

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
# LFS follows origin, and the bare mirror has no LFS endpoint — pin it back:
git config lfs.url https://github.com/google-ai-edge/LiteRT-LM.git/info/lfs
```

That last line is not optional. Redirecting `origin` fixes the `git fetch --tags` hang and immediately breaks `git lfs pull`, which then leaves pointer files in place of the accelerator dylibs — a failure that surfaces much later, as a dylib that loads but exports nothing.

Verify the LFS pull produced real binaries, not pointers — `head -c 20 <file>` starting with `version https` means it's still a pointer.

### ⚠️ NPU dispatch libraries MUST be rebuilt from the pin — never carried forward

**This section previously said the opposite.** It claimed both NPU stacks are unbuildable and must be copied from the previous release, and instructed asserting byte-identity against it. That was wrong, and it is the single most expensive mistake this skill has recorded: it turned two of our own configuration defects into upstream bug reports (#2957, #3217) that had to be retracted, and it is the direct cause of the Android NPU crash below.

Both dispatch libraries build from the same pin as the runtime:

| Bundle | Target | Notes |
|---|---|---|
| `windows_x86_64` | `@litert//litert/vendors/intel_openvino/dispatch:LiteRtDispatch` | Bazel fetches the OpenVino SDK itself (`configurable_repo`) — no preinstalled toolkit on the runner. Built in CI. |
| `android_arm64` | `//litert/vendors/qualcomm/dispatch:dispatch_api_so` | From the **LiteRT** repo at the derived `LITERT_REF`, not LiteRT-LM. Bazel auto-downloads QAIRT 2.44.0.260225 (~500 MB), or point `LITERT_QAIRT_SDK` at a local copy. Built locally by `build_qualcomm_dispatch.sh`. |

Why the old rule was believable and still wrong: a fresh LiteRT-LM build genuinely emits neither library, because neither lives in the LiteRT-LM tree — they are LiteRT vendor targets. "Absent from the output" was read as "unbuildable" instead of "wrong target".

**A stale dispatch library does not fail politely.** It is a plugin loaded into the runtime's address space and it shares the runtime's structs:

- **Windows.** Ours had been frozen since native-v0.11.0-b and shipped **OpenVino 2026.2.0**, while every LiteRT pin since has required **2026.3.0.dev20260622** (build 22242-561fc907ca4). Upstream's own `third_party/intel_openvino/openvino.bzl` warns that a mismatched pair leaves the Intel OV compiler plugin talking to the wrong `libopenvino_intel_npu_compiler` at runtime. That is what killed `engine_create` on `backend=npu`.
- **Android.** `libLiteRtDispatch_Qualcomm.so` was built against LiteRT `5c5b9ce6`. On v0.16.0 it SIGSEGVs inside `LiteRtDestroyOptions` the moment `engine_create` tears an options object down — a struct-layout mismatch, surfacing as a crash in the *runtime's* symbol, which reads as a runtime bug.

Both looked like clean regressions at a version boundary, because they were: the boundary is where upstream finally touched the code the frozen artifact depended on. **Verify a bisection's conclusion, not just its measurement** — "v0.13.1 works, v0.14.0 crashes" is a true measurement that says nothing about whose change is at fault when one input to the comparison never moved.

**The QNN runtime `.so`s must be refreshed with the dispatch, not carried forward.** They are not compiled from source — they come out of the QAIRT SDK — which makes "just keep the old ones" look safe. It is not: the dispatch you build negotiates an **API version** with them, and ours drifted into

```
E/litert: [qnn_manager.cc:349] Qnn System library version 1.8.0 is mismatched.
          The minimum supported version is 1.11.0.
E/litert: [dispatch_api.cc:139] Failed to set up QNN manager
E/litert: [dispatch_delegate.cc:131] No usable Dispatch runtime found
```

Bazel already downloaded the matching SDK while building the dispatch. Take them from there so both halves come from one QAIRT:

```bash
Q=$(find "$(bazel info output_base)/external/qairt" -maxdepth 0 2>/dev/null)
D=native/litert_lm/prebuilt/android_arm64
for f in libQnnSystem.so libQnnHtp.so libQnnHtpV{73,75,79,81}Stub.so; do cp -f "$Q/lib/aarch64-android/$f" "$D/"; done
for v in 73 75 79 81; do cp -f "$Q/lib/hexagon-v$v/unsigned/libQnnHtpV${v}Skel.so" "$D/"; done
```

`libQnnHtpV79Skel.so` in particular must be bundled: it is **absent from `/vendor/dsp/cdsp/` even on Qualcomm reference firmware**, so shipping it is required, not a workaround for unusual devices.

**Do not verify this by version string.** QNN carries two independent numberings — the SDK marketing version (`2.44.0.260225143659`, present in `libQnnHtp*.so`) and the per-component API version (`1.8.0` vs the required `1.11.0`) that actually gates loading. Matching the first says nothing about the second, and `libQnnSystem.so` — the exact file that broke — carries **no version string at all**, so a `strings | grep` check on it silently reports "no data" in a way that reads as "fine". Compare **file sizes against the SDK** instead; every one of our ten stale libs was visibly smaller than its QAIRT 2.44 counterpart.

Whatever the origin, assert the NPU file count per bundle before packing. Shipping without them fails no build and no CPU/GPU smoke test — only a user on `PreferredBackend.npu` finds out.

#### Windows CI specifics

- **Job timeout 150 minutes.** A cold Bazel cache plus the OpenVino fetch overruns anything shorter; 60 min was killing runs mid-link.
- **Exclude the Bazel output base from Defender.** Two consecutive runs died at ~52 min with `Couldn't delete action output directory: D:/b/execroot/litert_lm/bazel-out/_tmp/actions/stderr-NNNN (Permission denied)`. The build had *finished*; Defender was holding a per-action stderr file open during cleanup. `Add-MpPreference -ExclusionPath` on the output base, plus one warm-cache retry of the build step, turns a 52-minute loss into a two-minute one.
- **Allow-list the OpenVino components; never copy `runtime\bin` wholesale.** A blanket copy drags in the CPU/GPU/auto/hetero plugins, every model frontend, and a full parallel set of **debug builds** — and those are named `openvinod.dll`, `*_plugind.dll`, `*_frontendd.dll`, so a `_d.dll` filter misses all of them. Two near-identically named sets side by side is precisely how the OpenVino core binds the wrong plugin. The allow-list took the bundle from 45 files / 207 MB to 28 files / 96 MB:

  ```
  openvino.dll, openvino_intel_npu_plugin.dll, openvino_intel_npu_compiler.dll,
  openvino_intel_npu_compiler_loader.dll, openvino_tensorflow_lite_frontend.dll, tbb*
  ```

  TBB lives outside `runtime\bin` (`3rdparty\tbb\bin`), so search the whole SDK. `throw` on any missing member — a silently short NPU stack is the failure mode this whole section exists to prevent.

  The `tbb*` wildcard at the end of that list is itself a small leak: it also matches `tbb12_debug.dll`, `tbbbind_2_5_debug.dll`, `tbbmalloc_debug.dll` and `tbbmalloc_proxy_debug.dll`. Only ~1.9 MB of a 253 MB bundle, and unlike `openvinod.dll` the names are distinct enough not to be mis-bound, so it is dead weight rather than a hazard — but add `-and $_.Name -notlike '*_debug.dll'` next time the workflow is touched.

#### Qualcomm dispatch: `-gcc-toolchain` means you are building the wrong ref

`clang: error: unknown argument: '-gcc-toolchain'` looks like an NDK-version problem and is not one. It means the tree you are building resolves the Android toolchain through the **legacy** `--crosstool_top=//external:android/crosstool`, which wants the NDK ≤ r22 layout (`toolchains/aarch64-linux-android-4.9/`) that no modern NDK ships.

Only old LiteRT does that. Compare the two pins:

| | `5c5b9ce6` (our old hardcoded ref) | `0ff28117` (the v0.16.0 pin) |
|---|---|---|
| WORKSPACE | no `android_ndk_repository` at all | `rules_android_ndk` + `register_toolchains` |
| `build:android_arm64` | platforms only | adds `--incompatible_enable_cc_toolchain_resolution` and `--incompatible_enable_android_toolchain_resolution` |
| NDK 26+ | unsupported | supported (`# Need latest rules_android_ndk to use NDK 26+`) |

So the `-gcc-toolchain` failure was a **symptom of the hardcoded `LITERT_REF`**, not a separate constraint: the script was compiling a four-release-old tree that genuinely cannot use a modern NDK. Deriving the ref fixes the crash *and* the build. **NDK r29 is correct here** — same value `build_android.sh` requires, no per-invocation juggling.

Feed the NDK path with `--repo_env`, not `--action_env`:

```bash
bazelisk build --repo_env=ANDROID_NDK_HOME="$ANDROID_NDK_HOME" \
  --config=android_arm64 --compilation_mode=opt --strip=always \
  --linkopt=-Wl,-z,max-page-size=16384 \
  //litert/vendors/qualcomm/dispatch:dispatch_api_so
```

The new wiring gates on a repository rule — `check_android_ndk_env` calls `ctx.getenv("ANDROID_NDK_HOME")` and, when unset, registers `@android_ndk_env//:all`, a repo with an **empty BUILD file**. Zero toolchains, and the failure surfaces far from its cause. `--action_env` populates action environments, which repo rules never read; the generated `.litert_configure.bazelrc` (`--action_env ANDROID_NDK_HOME`, `ANDROID_NDK_API_LEVEL`, …) is the old TF-era mechanism and is dead weight at this pin — `api_level` now lives in the WORKSPACE call.

Expect ~3 minutes warm and a 707-724 KB stripped `ELF 64-bit aarch64` exporting exactly one symbol, `LiteRtDispatchGetApi`. Verify that symbol before packing; the library has no other public entry point, so its absence is the whole failure mode.

`bazelisk clean --expunge` between attempts only if you changed WORKSPACE-level wiring — Bazel caches toolchain resolution, and a cached failure re-prints the previous error without recompiling, which reads as "the fix didn't work".

---

## Build commands

Always pass the pinned SHA explicitly — the scripts' `DEFAULT_REF` lags the release you're migrating to.

```bash
REF=<tag-commit-sha>          # v0.16.0 = 924e79c91542761242244e4f1651851f822e4cbb
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/29.0.14206865"   # r29 mandatory

./native/litert_lm/build_macos.sh   "$REF"    # macOS arm64
./native/litert_lm/build_ios.sh     "$REF"    # iOS device + simulator
./native/litert_lm/build_android.sh "$REF"    # Android arm64, cross-compiled

# Qualcomm NPU dispatch — separate build, separate repo (LiteRT), separate NDK.
# Derives LITERT_REF from the LiteRT-LM WORKSPACE; see the NPU section above.
LITERTLM_REF="$REF" ./native/litert_lm/build_qualcomm_dispatch.sh
```

`ANDROID_NDK_HOME` must be **exported explicitly**: `build_android.sh` auto-detects the newest NDK *only when the variable is unset*, so a stale value in your shell silently selects the wrong toolchain (r26 fails on a C++20 concept in the minijinja chat template).

**Linux x86_64/arm64 and Windows x86_64 build in CI**, not on a VM: dispatch `build-litertlm-native.yml` with `-f litertlm_version=<SHA>`. Use `--ref <branch>` if the migration carries source changes — the workflow compiles `stream_proxy.c` from the checked-out tree **and** builds the Intel NPU dispatch, so dispatching from `main` would silently ship a stale shim and a stale dispatch.

`build-litertlm-native-windows.yml` is a Windows-only copy of that job for fast iteration. It duplicates the job body rather than sharing it — **when you change one, change both**, or the standalone workflow quietly builds with the previous release's flags.

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

`set -o pipefail` is not enough when the build is not the last command in the chain: `bazel … | tail -20` exits with `tail`'s status, and `build_macos.sh` reported success through a genuine failure that way. Put the build last, or capture `${PIPESTATUS[0]}`.

### Fetching artifacts is part of the build — verify those too

Both of our download paths fail silently:

- **`gh run download`** leaves an empty directory rather than erroring when the artifact name doesn't match, and has no `--clobber`, so a re-download into a populated directory can mix two runs' outputs. Always download into a **fresh** directory and assert the file count.
- **`curl`** exits `0` on a truncated transfer. One 2877 MB model arrived as 45 MB with a clean exit. Use `--retry 5 --retry-all-errors -C -` and verify the byte count against `Content-Length` before using the file.

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

**But note what it still does NOT cover** — see the next check.

### 7b. Build with `prebuilt/` moved aside — the only test of what users actually get

`_resolveLibDir` tries three sources in order: local `native/litert_lm/prebuilt/<dir>/`, then the version-scoped cache, then `_downloadAndExtract` from `native-v<version>`. **End users only ever reach the third** — `prebuilt/` is gitignored and ships in no pub package (confirm with `dart pub publish --dry-run | grep -ciE 'prebuilt|\.so$|\.dylib|\.dll'` → must be `0`).

On a maintainer machine the first source always hits. So every build you run locally — including check #7 and the release skill's `flutter build apk --release` pre-flight — silently validates **your** bundle and never touches the download, checksum verification, or extraction. Green means nothing about the artifact you are about to publish.

After the release exists and the hook's `_checksums` are updated, force the real path:

```bash
mv native/litert_lm/prebuilt /tmp/prebuilt-aside
rm -rf "$HOME/Library/Caches/flutter_gemma/native"     # kill the cache too, or you test source #2
cd example && flutter clean && flutter pub get && flutter build apk --release
mv /tmp/prebuilt-aside native/litert_lm/prebuilt
```

Pack the tarballs **from the exact directory you device-tested**, so the published bytes match the verified bytes by construction rather than by coincidence.

This is the same failure shape as the frozen NPU dispatches: local state standing in for what goes out the door.

### 8. (App Store-bound builds) Frameworks/ structural check

After `flutter build ipa --release` or archive:

```bash
ls Runner.app/Frameworks/
# → only *.framework directories. Zero loose .dylib files. Zero symlinks.
find Runner.app/Frameworks/ -maxdepth 1 -type l   # must be empty
find Runner.app/Frameworks/ -maxdepth 1 -name "*.dylib" -type f   # must be empty
```

If anything other than `.framework/` is in there, App Store will reject with ITMS-90432 ("Unexpected file found in Frameworks").

### 9. NPU on real silicon — the only check that covers the dispatch libraries

Nothing in checks 1–8 touches NPU. Both dispatch libraries load only when `PreferredBackend.npu` is requested on matching hardware, so they need real devices:

- **Intel NPU** — LunarLake/PantherLake. Our access is the Intel Tiber VM (see the `project_intel_npu_vm` memory). Run the litertlm smoke suite with `--plain-name "NPU"` **on its own**: inside the full file the NPU group runs after GPU, and async WebGPU teardown blows the per-test timer on the first NPU `engine_create`.
- **Qualcomm NPU** — Snapdragon 8 Gen 3 / 8 Elite. Ours is Qualcomm Device Cloud (QDC).

Both are slow, awkward, and easy to skip. Skipping them is what shipped the two frozen dispatch libraries described above.

#### QDC and Android instrumentation, in the order that works

QDC gives you an SSH tunnel that forwards the **ADB server port (5037)**, not a device port. Consequences:

1. `adb kill-server` **first**, then open the tunnel. A local ADB server already holding `127.0.0.1:5037` makes ssh bind IPv6 only, and the symptom is a device list that is simply empty.
2. `nohup … & disown` — there is no `setsid` on macOS, and with it the tunnel never starts at all.
3. `flutter test -d <device>` **cannot work here.** It needs `adb forward` for the Dart VM Service, and with the server itself proxied the forward binds on the remote side. Use an Espresso instrumentation run instead.
4. Sessions are time-capped (100 min standard, 300 on request). A tunnel that stops responding mid-run is usually just an expired session — check that before debugging the transport.

Building the instrumentation APK: `flutter build apk` is **wrong**, it packs `main.dart`. The app APK must carry the test entrypoint:

```bash
cd packages/flutter_gemma/example/android
./gradlew app:assembleDebug -Ptarget=<absolute path to integration_test/xxx_test.dart>
```

Verify the entrypoint actually landed with **binary** grep — `strings` misses it in the compiled kernel blob:

```bash
grep -ac "<a string unique to the test file>" app/build/outputs/apk/debug/app-debug.apk
```

And beware the Espresso idle timeout: `Could not launch intent within 45000 ms` is usually not a broken test but app startup doing real work — ours was restoring a 3 GB active model, so the main thread never went idle. Clear app state, or start from a build that doesn't auto-restore.

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
| 7 | NPU dispatch stacks dropped from the tarballs — packed without them | Count per bundle before packing | **caught pre-publish** at v0.14.0 *and* v0.15.0 |
| 8 | LiteRT pin moved, `LiteRtCreateModelFromFile` 2→3 args → embeddings `status=500` | Header diff at both `LITERT_REF`s | v0.14.0 dev cycle, ~1 day lost |
| 9 | `RTLD_DEFAULT` undeclared on glibc — needs `_GNU_SOURCE` before every include | CI Linux job (macOS compiles it happily) | **caught in CI** at v0.15.0 |
| 10 | v0.15.0 changed `LiteRtLmStreamCallback` 4-arg → 2-arg, no compat overload | ACCESS_VIOLATION (Windows) / malformed UTF-8 (macOS) at first token | **caught pre-publish** at v0.15.0 |
| 11 | `--define=litert_link_capi_so=true` deleted upstream — inert, statically linked runtime → Windows GPU `engine_create` crash | Grep the define in the tree being built | v0.14.0 → v0.16.0, **misfiled upstream as #2957** |
| 12 | Intel NPU dispatch carried forward at OpenVino 2026.2.0 against a pin requiring 2026.3.0 | Build the dispatch from the pin | v0.11.0-b → v0.16.0, **misfiled upstream as #3217** |
| 13 | Qualcomm dispatch hardcoded to LiteRT `5c5b9ce6` — SIGSEGV in `LiteRtDestroyOptions`, and `-gcc-toolchain` when rebuilt | Derive `LITERT_REF` from WORKSPACE; check #9 on device | native-v0.12.0 → v0.16.0; rebuilt, **device verification pending** |
| 14 | Blanket copy of OpenVino `runtime\bin` ships debug DLLs (`openvinod.dll`) beside release | Explicit allow-list + `throw` on missing | caught pre-publish at v0.16.0 |
| 15 | QNN runtime libs left at an old QAIRT while the dispatch moved — `Qnn System library version 1.8.0 is mismatched` | Check #9 on device; compare file sizes against the SDK | native-v0.12.0 → v0.16.0, **caught on device** |

Every one of those would have been caught by checks 1-9 before commit. **Run them all every time.**

Three patterns deserve emphasis because nothing in the build output hints at them:

- **#7, #12 and #13 are silent.** The tarball packs, the checksums verify, every smoke test on CPU/GPU passes. Only a user on `PreferredBackend.npu` finds out.
- **#8 and #10 are ABI drift, not code changes on our side.** C linkage means a stale call shape still links; you get register garbage instead of a compiler error. When a bump touches any callback or C-API signature, verify the shape at both refs rather than assuming source that compiles is source that's correct.
- **#11, #12 and #13 are the same organizational defect wearing three costumes.** Every one is an input we pinned once and stopped maintaining — a define, an SDK version, a commit SHA — that only misbehaves when upstream touches the code depending on it. Each surfaced at a version boundary and each was reported upstream before the real cause was found. **Before filing an upstream regression, list every input to the comparison and confirm which ones moved.** If one of them is ours and frozen, it is ours until proven otherwise.

---

## When upstream is broken

We import some dylibs as-is from upstream LiteRT-LM (`libGemmaModelConstraintProvider.dylib`, `libLiteRtMetalAccelerator.dylib`, sampler dylibs). When upstream ships them with insufficient headerpad / wrong arch / broken exports:

1. **Rule out our own frozen inputs first.** Before writing the issue, enumerate every input to the failing comparison — defines, SDK versions, pinned SHAs, carried-forward binaries — and confirm which ones actually moved between the working and broken versions. Two of our four most recent upstream reports (#2957, #3217) were our configuration and had to be retracted; in both the "regression" was upstream finally exercising something we had frozen years earlier. A bisection that lands on a version boundary tells you *when*, never *whose*.
2. **File an issue with reproducer** — see `project_litertlm_upstream_*` memories for our open ones (#1990, #2072, #2073, #2080).
3. **Don't ship them blindly.** Run check #4 (install_name_tool smoke) on every upstream-sourced dylib **before** copying to `prebuilt/`. If it fails, **don't publish** — find a workaround first (relink, or ship without that lib + change Dart code path).
4. **Add a memory entry** documenting the bug + workaround in `~/.claude/projects/.../memory/project_*.md` so future sessions don't re-discover it.

---

## After successful build

1. **Run the verification checklist 1-9 above. All checks must pass.**
2. Commit the new dylibs (`git add prebuilt/<dir>/*.dylib`)
3. Pack tarballs + update `hook/build.dart` `_checksums` + re-upload to GitHub Release `native-v<version>` (see `release` skill).
4. Run `dart pub publish --dry-run` — must show 0 warnings.
5. Only then publish.
