#!/usr/bin/env bash
#
# Analyze, test and format-check every codelab step app under codelabs/.
#
# Each step is a standalone app that depends on the PUBLISHED packages, exactly
# like a learner's checkout — so this is also an early warning that a release
# broke the teaching material. Run nightly for that reason, not just on push.
#
# Apps are discovered, not listed, so adding a codelab needs no edit here.
set -euo pipefail

cd "$(dirname "$0")/.."

# The depth is exactly codelabs/<codelab-id>/<step>/pubspec.yaml, so
# -mindepth 3 -maxdepth 3 both skips a pubspec.yaml sitting higher up (there is
# none today, and if one appears it is not a step app) and cannot descend into
# a build/ or .dart_tool/ directory.
# Portable collection: `mapfile` is bash 4+, and macOS still ships bash 3.2,
# so the script would silently do nothing on a maintainer's laptop.
APPS=()
while IFS= read -r line; do
  APPS+=("$line")
done < <(find codelabs -mindepth 3 -maxdepth 3 -name pubspec.yaml \
           -not -path '*/_*' -print | sort)

# Fail closed. A discovery bug that finds nothing must not read as "all green".
if [ "${#APPS[@]}" -eq 0 ]; then
  echo "::error::no codelab apps found under codelabs/ — discovery is broken"
  exit 1
fi

echo "Found ${#APPS[@]} codelab step app(s)."
failed=0

for pubspec in "${APPS[@]}"; do
  app="$(dirname "$pubspec")"
  echo ""
  echo "=== $app ==="
  (
    cd "$app"
    flutter pub get
    flutter analyze
    # `flutter analyze` covers integration_test/ where it exists, so the
    # format check has to as well — otherwise drift there passes CI. Not
    # `dart format .`, which would also walk build/ on a maintainer's machine.
    fmt_dirs=(lib test)
    if [ -d integration_test ]; then fmt_dirs+=(integration_test); fi
    dart format --output=none --set-exit-if-changed "${fmt_dirs[@]}"
    # integration_test/ suites need a device and a multi-hundred-MB model
    # download; they are deliberately not RUN by this gate.
    flutter test
  ) || { echo "::error::$app failed"; failed=1; }
done

# One real compile, per codelab. `flutter analyze` type-checks Dart and stops
# there; it never opens web/index.html, never runs the web compiler, and would
# not notice a step app whose platform directories are missing or malformed.
# Web is the one target a Linux CI runner can build for all six-platform apps —
# Android needs an SDK, Apple targets need a Mac, Windows needs Windows — so it
# is the only build this gate can honestly claim. Only the two `complete/` apps
# are built: they are supersets of their own steps, and a build is ~20 s each.
built=0
for app in codelabs/*/complete; do
  echo ""
  echo "=== $app: flutter build web --release ==="
  ( cd "$app" && flutter build web --release ) \
    || { echo "::error::$app failed to build for web"; failed=1; }
  built=$((built + 1))
done

# Fail closed, the way discovery does above. Every codelab has a `complete/` —
# it is the finished app both texts point the learner at — so the number of
# builds has to equal the number of codelabs. Rename or drop one and the glob
# quietly skips it: a build that never ran must not read as one that passed.
codelab_count="$(printf '%s\n' "${APPS[@]}" | cut -d/ -f2 | sort -u | wc -l | tr -d ' ')"
if [ "$built" -ne "$codelab_count" ]; then
  echo "::error::built $built web app(s) for $codelab_count codelab(s) — a complete/ directory is missing or renamed"
  failed=1
fi

# Cross-codelab invariants, declared rather than hand-checked: a later codelab's
# starter IS an earlier codelab's finished app, and both texts tell the learner
# so. Without this the property drifts the first time someone edits one side.
MIRRORS=(
  "codelabs/getting-started-flutter-gemma/complete|codelabs/inference-engines-flutter-gemma/step_01_starter"
)

for pair in "${MIRRORS[@]}"; do
  src="${pair%%|*}"
  dst="${pair##*|}"
  echo ""
  echo "=== $dst must equal $src (lib, test) ==="
  for sub in lib test; do
    # Fail closed: a renamed directory must not read as "nothing to compare".
    if [ ! -d "$src/$sub" ] || [ ! -d "$dst/$sub" ]; then
      echo "::error::$src/$sub or $dst/$sub is missing — the mirror check cannot run"
      failed=1
      continue
    fi
    diff -r "$src/$sub" "$dst/$sub" \
      || { echo "::error::$dst/$sub has drifted from $src/$sub"; failed=1; }
  done
done

exit "$failed"
