#!/usr/bin/env bash
# Build a sqlite3.wasm with sqlite-vec (vec0) statically linked in, for the web
# arm of flutter_gemma_rag_sqlite. Proven end-to-end (PoC #2, 2026-06-21): the
# resulting wasm runs in headless Chromium, vec0 KNN returns TEXT ids — see
# tool/verify_web_vec0.mjs.
#
# WHY a custom build: the published sqlite3.wasm has no vector extension, and
# load_extension at runtime is unavailable in the browser. We compile sqlite-vec
# into the wasm with -DSQLITE_CORE and auto-register it (see the two patches in
# tool/sqlite_vec_patches/), so vec0 is present on every connection.
#
# Strategy: clone simolus3/sqlite3.dart, drop our two patched C files + the
# sqlite-vec amalgamation into its wasm build tree, splice three lines into its
# (live, not vendored) CMakeLists so the apphangs survive upstream drift, then
# run the repo's own WASI-clang + binaryen build. Output: build/out/sqlite3.wasm.
#
# Prerequisites (one-time; already installed on the dev box):
#   - wasi-sdk      → $WASI_SDK            (default /tmp/wasi-sdk)
#   - binaryen      → wasm-opt, wasm-ctor-eval on PATH (brew install binaryen)
#   - cmake >= 3.24, dart, git, curl
#
# Usage:
#   tool/build_vec0_wasm.sh [output_dir]
#   WASI_SDK=/opt/wasi-sdk SQLITE_VEC_VERSION=v0.1.9 tool/build_vec0_wasm.sh
set -euo pipefail

# ---- config (override via env) ---------------------------------------------
WASI_SDK="${WASI_SDK:-/tmp/wasi-sdk}"
SQLITE3DART_REF="${SQLITE3DART_REF:-6186376}"   # simolus3/sqlite3.dart pin (PoC)
SQLITE_VEC_VERSION="${SQLITE_VEC_VERSION:-v0.1.9}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES="$HERE/sqlite_vec_patches"
OUT_DIR="${1:-$HERE/../web/rag}"               # where the final sqlite3.wasm lands
WORK="${WORK:-$(mktemp -d)/sqlite3dart}"

CLANG="$WASI_SDK/bin/clang"
SYSROOT="$WASI_SDK/share/wasi-sysroot"

echo "==> wasi-sdk:        $WASI_SDK"
echo "==> sqlite3.dart:    simolus3@$SQLITE3DART_REF"
echo "==> sqlite-vec:      $SQLITE_VEC_VERSION"
echo "==> work dir:        $WORK"
echo "==> output:          $OUT_DIR"

for bin in "$CLANG" cmake dart git curl wasm-opt wasm-ctor-eval; do
  command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ] || {
    echo "ERROR: missing prerequisite: $bin" >&2; exit 1; }
done
[ -d "$SYSROOT" ] || { echo "ERROR: wasi-sysroot not found at $SYSROOT" >&2; exit 1; }

# ---- 1. clone sqlite3.dart at the pinned ref --------------------------------
rm -rf "$WORK"
git clone --no-checkout https://github.com/simolus3/sqlite3.dart.git "$WORK"
git -C "$WORK" checkout "$SQLITE3DART_REF"

SRC="$WORK/sqlite3/assets/wasm"   # upstream wasm build tree (path per ref)
[ -d "$SRC" ] || SRC="$WORK/sqlite3_wasm_build"  # older layout fallback
[ -d "$SRC/src" ] || { echo "ERROR: wasm build tree not found under $WORK" >&2; exit 1; }
echo "==> wasm build tree: $SRC"

# ---- 2. fetch the sqlite-vec amalgamation -----------------------------------
VEC_URL="https://github.com/asg017/sqlite-vec/releases/download/$SQLITE_VEC_VERSION/sqlite-vec-${SQLITE_VEC_VERSION#v}-amalgamation.tar.gz"
echo "==> fetching sqlite-vec amalgamation: $VEC_URL"
TMP_VEC="$(mktemp -d)"
curl -fsSL "$VEC_URL" -o "$TMP_VEC/vec.tar.gz"
tar -xzf "$TMP_VEC/vec.tar.gz" -C "$TMP_VEC"
cp "$TMP_VEC"/sqlite-vec.c "$SRC/src/sqlite-vec.c"
cp "$TMP_VEC"/sqlite-vec.h "$SRC/src/sqlite-vec.h"

# ---- 3. apply our two C patches (auto-register + WASI random_get stub) -------
cp "$PATCHES/os_web.c"     "$SRC/src/os_web.c"
cp "$PATCHES/getentropy.c" "$SRC/src/getentropy.c"

# ---- 4. splice three lines into the LIVE upstream CMakeLists -----------------
# (a) add the two extra source files to the build's `sources` list;
# (b) add -DSQLITE_CORE so sqlite-vec links as a core extension.
CML="$SRC/src/CMakeLists.txt"
if ! grep -q "sqlite-vec.c" "$CML"; then
  perl -0pi -e 's{(\$\{CMAKE_CURRENT_SOURCE_DIR\}/os_web.c)}{$1\n    ${CMAKE_CURRENT_SOURCE_DIR}/sqlite-vec.c\n    ${CMAKE_CURRENT_SOURCE_DIR}/getentropy.c}' "$CML"
fi
if ! grep -q "SQLITE_CORE" "$CML"; then
  perl -0pi -e 's{(set\(flags -Wall -Wextra[^\)]*)}{$1 -DSQLITE_CORE}' "$CML"
fi
grep -q "sqlite-vec.c" "$CML" || { echo "ERROR: CMakeLists splice (sources) failed" >&2; exit 1; }
grep -q "SQLITE_CORE"  "$CML" || { echo "ERROR: CMakeLists splice (SQLITE_CORE) failed" >&2; exit 1; }
echo "==> CMakeLists patched (sqlite-vec sources + -DSQLITE_CORE)"

# ---- 5. build via the repo's own WASI-clang + binaryen pipeline --------------
BUILD="$SRC/build"
rm -rf "$BUILD"
cmake -S "$SRC/src" -B "$BUILD" \
  -Dclang="$CLANG" \
  -Dwasi_sysroot="$SYSROOT"
cmake --build "$BUILD" --target output

# ---- 6. publish the artifact ------------------------------------------------
mkdir -p "$OUT_DIR"
cp "$SRC/out/sqlite3.wasm" "$OUT_DIR/sqlite3.wasm"
echo "==> DONE: $OUT_DIR/sqlite3.wasm ($(du -h "$OUT_DIR/sqlite3.wasm" | cut -f1))"
echo "==> verify it loads + vec0 KNN works in a browser with: tool/verify_web_vec0.mjs"
