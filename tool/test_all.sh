#!/usr/bin/env bash
# test_all.sh — run every workspace package's tests, from the package's own dir.
#
# WHY THIS EXISTS
#
# `flutter test` at the repo root tests nothing: the workspace root has no
# test/ directory. Pointing it at a package (`flutter test packages/<pkg>`)
# runs from the WRONG working directory — several suites read fixtures through
# paths relative to the package root (flutter_gemma_agent's
# test/fixtures/skills/*.SKILL.md), and 20 of them fail on a missing file.
#
# Until 2026-08-18 CI ran only packages/flutter_gemma, leaving 97 of the repo's
# 169 test files unexercised — all 46 in speech, all 14 in agent — while those
# packages publish to pub.dev independently, each under its own version.
#
# Packages are DISCOVERED, never listed. A hardcoded list is how a new
# satellite ends up shipping untested: it simply never appears in the run.
# Every workspace package is reported as either tested or having no test/
# directory, and a run that discovers nothing fails rather than reporting
# success — a check that examined nothing is not a check that passed.
#
# Usage:
#   tool/test_all.sh              # all packages
#   tool/test_all.sh --coverage   # plus lcov for flutter_gemma (what CI does)
#
# Exit: 0 all green · 1 any package failed, or nothing was discovered.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

WANT_COVERAGE=0
[[ "${1:-}" == "--coverage" ]] && WANT_COVERAGE=1

# SqliteVectorStore resolves its vec0 loadable through Native Assets — on macOS
# that is `vec0.framework/vec0`, which exists only inside a built app, never
# under `flutter test` on the host. The store already honours $VEC0_DYLIB as an
# override (sqlite_vector_store.dart:77) and this repo ships the loadable for
# every platform, so point at it.
#
# Without this those 20 store tests fail on a dlopen. They used to SKIP instead,
# gated on $VEC0_DYLIB being set — which it never was — so a suite that had
# never once executed looked exactly like a suite that passed.
if [[ -z "${VEC0_DYLIB:-}" ]]; then
  case "$(uname -s)" in
    Darwin) _vec0_rel="packages/flutter_gemma_rag_sqlite/native/sqlite_vec/prebuilt/macos_arm64/libvec0.dylib" ;;
    Linux)  _vec0_rel="packages/flutter_gemma_rag_sqlite/native/sqlite_vec/prebuilt/linux_x86_64/libvec0.so" ;;
    *)      _vec0_rel="" ;;
  esac
  if [[ -n "$_vec0_rel" && -f "$_vec0_rel" ]]; then
    export VEC0_DYLIB="$PWD/$_vec0_rel"   # absolute: suites run from their own dir
    echo "==> VEC0_DYLIB=$VEC0_DYLIB"
  else
    echo "==> no prebuilt vec0 for $(uname -s); rag_sqlite's store suites will skip"
  fi
fi

fail=0 tested=0 untested=0 total=0
summary=""

for dir in packages/*/; do
  pkg="$(basename "$dir")"
  [[ -f "${dir}pubspec.yaml" ]] || continue
  total=$((total + 1))

  if ! find "${dir}test" -name '*_test.dart' 2>/dev/null | grep -q .; then
    summary="${summary}  --  ${pkg}: no test/ directory"$'\n'
    untested=$((untested + 1))
    continue
  fi

  # Coverage only for core; that is what Codecov consumes.
  # No --reporter: on GitHub Actions the default is already the `github`
  # reporter, and naming any other one downgrades it.
  #
  # Spelled as two branches rather than an args array on purpose: macOS still
  # ships bash 3.2, where `set -u` plus an EMPTY array expansion is an
  # "unbound variable" error. CI runs bash 5 and would never have shown it —
  # this script is meant to be run locally too.
  echo "::group::flutter test — $pkg"
  if [[ $WANT_COVERAGE -eq 1 && "$pkg" == "flutter_gemma" ]]; then
    (cd "$dir" && flutter test --coverage)
  else
    (cd "$dir" && flutter test)
  fi
  rc=$?
  echo "::endgroup::"

  if [[ $rc -eq 0 ]]; then
    summary="${summary}  ok  ${pkg}"$'\n'
  else
    summary="${summary}  FAILED  ${pkg}"$'\n'
    fail=1
  fi
  tested=$((tested + 1))
done

echo
echo "==> Test coverage across the workspace"
printf '%s' "$summary"
echo "    ${tested} package(s) tested, ${untested} without tests, ${total} total."

if [[ $total -eq 0 ]]; then
  echo "::error::Discovered no packages under packages/*/ — the glob or the repo"
  echo "::error::layout changed. A run that tested nothing is not a pass."
  exit 1
fi
if [[ $tested -eq 0 ]]; then
  echo "::error::Found ${total} package(s) but none with a test/ directory."
  exit 1
fi

exit "$fail"
