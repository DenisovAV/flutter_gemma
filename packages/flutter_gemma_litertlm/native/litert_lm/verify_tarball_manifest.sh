#!/usr/bin/env bash
# verify_tarball_manifest.sh — release gate that catches DROPPED native files.
#
# THE BUG THIS PREVENTS (native-v0.13.1, 1.0.0): rebuilding native for a new
# LiteRT-LM version silently shipped WITHOUT the manually-built NPU add-on
# stacks — android lost 11 Qualcomm/QNN libs, windows lost 12 Intel OpenVino/
# TBB files. `PreferredBackend.npu` broke on both. Nothing caught it: the
# release skill's "dylibs changed?" step diffs a GITIGNORED prebuilt/ dir, and
# the FFI gate only exercises GPU/CPU, never NPU. So the only safety net is
# comparing the NEW tarball's file-list against the LAST PUBLISHED tag.
#
# What it does: for every litertlm-<plat>.tar.gz you are about to publish, it
# downloads the same archive from the previous tag and DIFFS the file lists.
# Any file present in the old tag but MISSING in the new one is a hard FAIL
# (exit 1) — unless explicitly allow-listed via INTENTIONAL_DROPS.
#
# Usage:
#   ./verify_tarball_manifest.sh <DIST_DIR> <PREV_TAG>
#   ./verify_tarball_manifest.sh "$DIST" native-v0.13.1
#
# Intentional removals (e.g. you really meant to drop a lib) go in
# INTENTIONAL_DROPS below, one "plat:filename" per line, with a comment saying
# why. An empty/default list means "nothing may disappear".

set -euo pipefail

DIST_DIR="${1:?usage: verify_tarball_manifest.sh <DIST_DIR> <PREV_TAG>}"
PREV_TAG="${2:?usage: verify_tarball_manifest.sh <DIST_DIR> <PREV_TAG>}"
REPO="${FLUTTER_GEMMA_REPO:-DenisovAV/flutter_gemma}"

# Allow-list of files that are INTENTIONALLY removed in this release.
# Format: "<platform>:<basename>" (e.g. "android_arm64:libQnnHtp.so").
# Keep this EMPTY unless you are deliberately dropping a file — every entry
# needs a comment explaining why, so the gate stays meaningful.
INTENTIONAL_DROPS=(
  # native-v0.17.0: #437 stages release TBB only. native-v0.16.0 was packed
  # before it landed and still carried the parallel debug set.
  "windows_x86_64:tbb12_debug.dll"
  "windows_x86_64:tbbbind_2_5_debug.dll"
  "windows_x86_64:tbbmalloc_debug.dll"
  "windows_x86_64:tbbmalloc_proxy_debug.dll"
)

_is_intentional() {
  local key="$1"
  for d in "${INTENTIONAL_DROPS[@]:-}"; do
    [[ "$d" == "$key" ]] && return 0
  done
  return 1
}

PREV_DL="$(mktemp -d)"
trap 'rm -rf "$PREV_DL"' EXIT

echo "==> Verifying new tarballs in $DIST_DIR against previous tag $PREV_TAG"
echo "    repo: $REPO"
echo

# Enumerate the previous tag's assets ONCE, up front. Failing to read this list
# is a failure to LEARN what shipped last time — it is NOT evidence that a file
# is absent, so it must never be reported as a skip. Hard-fail instead.
if ! prev_assets="$(gh release view "$PREV_TAG" --repo "$REPO" \
      --json assets --jq '.assets[].name' 2>&1)"; then
  echo "❌ Cannot read the asset list of $PREV_TAG from $REPO." >&2
  echo "   gh said: $prev_assets" >&2
  echo "   This gate compares against that tag, so it cannot run at all." >&2
  echo "   Fix access (gh auth status) or the tag name, then re-run." >&2
  echo "   Do NOT publish on the strength of a check that did not execute." >&2
  exit 2
fi

_prev_has() {
  printf '%s\n' "$prev_assets" | grep -qxF "$1"
}

fail=0
checked=0
skipped=0

for new in "$DIST_DIR"/litertlm-*.tar.gz; do
  [[ -e "$new" ]] || { echo "No litertlm-*.tar.gz found in $DIST_DIR" >&2; exit 2; }
  base="$(basename "$new")"                 # litertlm-android_arm64.tar.gz
  plat="${base#litertlm-}"; plat="${plat%.tar.gz}"

  # Two different outcomes used to collapse into one skip here. Keep them apart:
  # "the previous tag has no such asset" is a legitimate skip (new platform),
  # while "the asset is listed but would not download" means we cannot compare —
  # a hard failure, not a pass.
  if ! _prev_has "$base"; then
    echo "  [skip] $plat — '$base' is not an asset of $PREV_TAG (new platform)"
    skipped=$((skipped + 1))
    continue
  fi

  # One shot used to be enough until a 98 MB windows_x86_64 timed out and
  # failed the whole gate on native-v0.17.1. Retry, then fail closed — a
  # platform we could not diff must never read as a pass.
  dl_ok=0
  for attempt in 1 2 3; do
    if gh release download "$PREV_TAG" --repo "$REPO" --pattern "$base" \
          --dir "$PREV_DL" --clobber >/dev/null 2>&1; then
      dl_ok=1
      break
    fi
    sleep $((attempt * 5))
  done
  if [ "$dl_ok" -eq 0 ]; then
    echo "  [FAIL] $plat — '$base' IS an asset of $PREV_TAG but would not download."
    echo "         Cannot diff it, so this run proves nothing about $plat."
    fail=1
    continue
  fi

  checked=$((checked + 1))
  # Normalise a leading `./` (the `tar -C dir .` layout) and drop directory
  # entries and blanks — they aren't files. Without the normalisation a
  # `./`-prefixed archive diffs wholesale against a non-`./` one.
  #
  # Compare FULL PATHS, not basenames. `xargs -n1 basename` used to flatten the
  # tree, so `./libQnnHtp.so` -> `./nested/libQnnHtp.so` read as "no files
  # dropped" plus a reassuring "new files (ok): nested" — while the hook's flat
  # extraction would no longer find it. A relocation is a drop.
  _list() {
    tar -tzf "$1" \
      | sed 's|^\./||' \
      | grep -vE '/$' \
      | grep -vE '^\.?$' \
      | sort -u
  }
  old_list="$(_list "$PREV_DL/$base")"
  new_list="$(_list "$new")"

  # Files in OLD but not in NEW = dropped.
  dropped="$(comm -23 <(printf '%s\n' "$old_list") <(printf '%s\n' "$new_list"))"
  added="$(comm -13 <(printf '%s\n' "$old_list") <(printf '%s\n' "$new_list"))"

  if [[ -n "$added" ]]; then
    echo "  [info] $plat — new files (ok): $(echo "$added" | tr '\n' ' ')"
  fi

  if [[ -z "$dropped" ]]; then
    echo "  [ok]   $plat — no files dropped"
    continue
  fi

  # Some files dropped — fail unless every one is allow-listed.
  local_fail=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if _is_intentional "$plat:$f"; then
      echo "  [allow] $plat — intentionally dropped: $f"
    else
      echo "  [FAIL] $plat — MISSING from new tarball: $f"
      local_fail=1
    fi
  done <<< "$dropped"

  [[ $local_fail -eq 1 ]] && fail=1
done

# The loop above walks the NEW tarballs, so a platform that vanished entirely
# is invisible to it: pack only windows when the previous tag had windows and
# android, and it reports "1 platform(s) compared" and exits 0. That is the same
# defect the gate exists to catch, one level up — "android was never rebuilt"
# instead of "a file inside android went missing". Walk the other direction too.
missing_plat=0
while IFS= read -r asset; do
  [[ "$asset" == litertlm-*.tar.gz ]] || continue
  if [[ ! -e "$DIST_DIR/$asset" ]]; then
    plat="${asset#litertlm-}"; plat="${plat%.tar.gz}"
    echo "  [FAIL] $plat — '$asset' is in $PREV_TAG but was not packed at all."
    echo "         The platform was not rebuilt, or packing skipped it."
    missing_plat=1
  fi
done <<< "$prev_assets"
[[ $missing_plat -eq 1 ]] && fail=1

# Page alignment. The manifest check above answers "is every file still here";
# it cannot see that a file arrived misaligned. Google Play rejects an APK in
# which any .so has a PT_LOAD p_align below 16 KB, and the Qualcomm Skel blobs
# ship from the QAIRT SDK at 0x1000 — so this slipped through every build,
# every test and the manifest gate, and surfaced as a store rejection in a
# consumer's app (#529). Look inside the archives, not just at their listings.
echo
echo "==> Checking 16 KB page alignment inside each tarball"
align_tmp="$(mktemp -d)"
trap 'rm -rf "$align_tmp"' EXIT
align_fail=0
for new in "$DIST_DIR"/litertlm-*.tar.gz; do
  [[ -e "$new" ]] || continue
  name="$(basename "$new")"
  dest="$align_tmp/${name%.tar.gz}"
  mkdir -p "$dest"
  tar -xzf "$new" -C "$dest"
  enforce=0
  case "$name" in litertlm-android_*) enforce=1 ;; esac
  if ! python3 - "$dest" "$name" "$enforce" <<'PYALIGN'
import glob, os, struct, sys

ALIGN = 0x4000
root, name, enforce = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
bad, checked = [], 0
for path in sorted(glob.glob(os.path.join(root, "**", "*.so"), recursive=True)
                   + glob.glob(os.path.join(root, "**", "*.dylib"), recursive=True)):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        continue                      # Mach-O / PE are not page-gated by Play
    if data[4] == 2:
        phoff = struct.unpack_from("<Q", data, 0x20)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
        o_al, word = 0x30, "<Q"
    else:
        phoff = struct.unpack_from("<I", data, 0x1C)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
        o_al, word = 0x1C, "<I"
    aligns = [struct.unpack_from(word, data, phoff + i * phentsize + o_al)[0]
              for i in range(phnum)
              if struct.unpack_from("<I", data, phoff + i * phentsize)[0] == 1]
    if not aligns:
        continue
    checked += 1
    if min(aligns) < ALIGN:
        bad.append((os.path.basename(path), hex(min(aligns))))
if bad and enforce:
    print(f"  [FAIL] {name} — {len(bad)} of {checked} ELF object(s) below 16 KB:")
    for n, a in bad:
        print(f"         {n}  p_align={a}")
    sys.exit(1)
if bad:
    # Not Android, so Play never sees it: an x86_64 linker defaults p_align to
    # the 4 KB page it targets, and that is correct there. Printed, not failed.
    print(f"  [info] {name} — {len(bad)} of {checked} ELF object(s) below 16 KB "
          f"(not an APK payload, so not gated)")
elif checked == 0 and enforce:
    # The one bundle this gate exists for, with nothing in it to gate. That is a
    # broken archive or a wrong path, never a pass — "inspected nothing" and
    # "found nothing wrong" must not share an exit code.
    print(f"  [FAIL] {name} — no ELF objects found at all; the archive or the "
          f"path is wrong, so nothing was verified")
    sys.exit(1)
elif checked == 0:
    print(f"  [info] {name} — no ELF objects (Mach-O or PE bundle), nothing to check")
else:
    print(f"  [ok]   {name} — {checked} ELF object(s), all 16 KB-aligned")
PYALIGN
  then
    align_fail=1
  fi
done
if [[ $align_fail -eq 1 ]]; then
  echo
  echo "❌ ALIGNMENT CHECK FAILED — Google Play will reject any app shipping this."
  echo "   Rebuild with build_qualcomm_dispatch.sh, which raises p_align on the"
  echo "   Qualcomm blobs, or take an aligned build from the SDK."
  exit 1
fi

echo
if [[ $checked -eq 0 ]]; then
  echo "❌ MANIFEST CHECK DID NOT RUN — zero platforms compared."
  echo "   $skipped tarball(s) had no counterpart in $PREV_TAG."
  echo "   A check that compared nothing is not a check that passed; if every"
  echo "   platform really is new, you are comparing against the wrong tag."
  exit 1
fi

if [[ $fail -eq 1 ]]; then
  echo "❌ MANIFEST CHECK FAILED — files disappeared vs $PREV_TAG."
  echo "   If a removal is intentional, add it to INTENTIONAL_DROPS with a reason."
  echo "   Otherwise a build step (e.g. build_qualcomm_dispatch.sh / Intel NPU"
  echo "   staging) did not run — rebuild before publishing."
  exit 1
fi

echo "✅ MANIFEST CHECK PASSED — $checked platform(s) compared against $PREV_TAG, no unexplained file drops."
if [[ $skipped -gt 0 ]]; then
  echo "   ($skipped tarball(s) skipped as new platforms.)"
fi
