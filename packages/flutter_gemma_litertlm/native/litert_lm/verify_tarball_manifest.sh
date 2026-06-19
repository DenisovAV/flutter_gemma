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
  # e.g. "windows_x86_64:tbb12_debug.dll"  # dropped debug TBB, prod-only ship
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

fail=0
checked=0

for new in "$DIST_DIR"/litertlm-*.tar.gz; do
  [[ -e "$new" ]] || { echo "No litertlm-*.tar.gz found in $DIST_DIR" >&2; exit 2; }
  base="$(basename "$new")"                 # litertlm-android_arm64.tar.gz
  plat="${base#litertlm-}"; plat="${plat%.tar.gz}"

  # Fetch the same archive from the previous tag. If the platform is new
  # (didn't exist in the previous tag), skip — nothing to compare against.
  if ! gh release download "$PREV_TAG" --repo "$REPO" --pattern "$base" \
        --dir "$PREV_DL" --clobber >/dev/null 2>&1; then
    echo "  [skip] $plat — '$base' not in $PREV_TAG (new platform?)"
    continue
  fi

  checked=$((checked + 1))
  # Strip the tar dir entry (`.` from `tar -C dir .` layout) and blanks — they
  # aren't files. Without this, a `./`-prefixed archive yields a spurious
  # "MISSING: ." against a non-`./` one (the two layouts list the dir slot
  # differently). basename of "./" is "." → filtered here.
  old_list="$(tar -tzf "$PREV_DL/$base" | xargs -n1 basename | grep -vE '^\.?$' | sort -u)"
  new_list="$(tar -tzf "$new"           | xargs -n1 basename | grep -vE '^\.?$' | sort -u)"

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

echo
if [[ $checked -eq 0 ]]; then
  echo "WARNING: no platforms compared (none of the new tarballs existed in $PREV_TAG)." >&2
fi

if [[ $fail -eq 1 ]]; then
  echo "❌ MANIFEST CHECK FAILED — files disappeared vs $PREV_TAG."
  echo "   If a removal is intentional, add it to INTENTIONAL_DROPS with a reason."
  echo "   Otherwise a build step (e.g. build_qualcomm_dispatch.sh / Intel NPU"
  echo "   staging) did not run — rebuild before publishing."
  exit 1
fi

echo "✅ MANIFEST CHECK PASSED — no unexplained file drops vs $PREV_TAG."
