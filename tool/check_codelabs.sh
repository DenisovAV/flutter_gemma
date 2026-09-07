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
    cd "$app" || exit 1
    # `flutter analyze` covers integration_test/ where it exists, so the format
    # check has to as well — otherwise drift there passes CI. Not `dart format .`,
    # which would also walk build/ on a maintainer's machine.
    fmt_dirs=(lib test)
    if [ -d integration_test ]; then fmt_dirs+=(integration_test); fi

    # One `&&` chain, deliberately: `set -e` does NOT apply inside a compound
    # command on the left of `||`, so with plain newlines this subshell's exit
    # status was whatever the LAST command returned. `flutter analyze` and the
    # format check failed silently for every app until this was chained.
    # integration_test/ suites need a device and a multi-hundred-MB model
    # download; they are deliberately not RUN here.
    flutter pub get &&
    flutter analyze &&
    dart format --output=none --set-exit-if-changed "${fmt_dirs[@]}" &&
    flutter test
  ) || { echo "::error::$app failed"; failed=1; }
done

# One real compile, per codelab. `flutter analyze` type-checks Dart and stops
# there; it never opens web/index.html, never runs the web compiler, and would
# not notice a step app whose platform directories are missing or malformed.
# Web is the one target a Linux CI runner can build for all six-platform apps —
# Android needs an SDK, Apple targets need a Mac, Windows needs Windows — so it
# is the only build this gate can honestly claim. One `complete/` per codelab is
# built and no other step: a `complete/` is a superset of its own steps, and a
# build is ~20 s each.
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
#
# One source can feed several starters — Getting Started's finished app is where
# both of the codelabs that continue it begin — so this is a list of pairs, not
# a map, and a new row is all a new continuation needs.
MIRRORS=(
  "codelabs/getting-started-flutter-gemma/complete|codelabs/inference-engines-flutter-gemma/step_01_starter"
  "codelabs/getting-started-flutter-gemma/complete|codelabs/multimodal-flutter-gemma/step_01_starter"
  "codelabs/getting-started-flutter-gemma/complete|codelabs/function-calling-flutter-gemma/step_01_starter"
)

# Fail closed, the way discovery does above. An emptied or mistyped table must
# not read as "every mirror holds"; there is at least one real pair today.
if [ "${#MIRRORS[@]}" -eq 0 ]; then
  echo "::error::MIRRORS is empty — the cross-codelab check cannot run"
  exit 1
fi

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

# One identity per codelab, and the two halves pull in opposite directions, so
# both are asserted:
#
#   1. Every app INSIDE a codelab declares the SAME id. That is what lets Step 3
#      open the model Step 2 downloaded — a promise every codelab text makes.
#   2. No two codelabs share one. Three of them once shipped as
#      dev.fluttergemma.gemma_quickstart: one Android install and one macOS
#      container between them, so the multimodal app opened with Getting
#      Started's model already "installed" — a model it never downloaded and
#      could not use.
#
# Per platform, because each keys its own container and one codelab is
# deliberately on a different prefix on Apple than it is on Linux. A platform
# that carries no id (a Windows app stores under %LOCALAPPDATA%, which is
# app-independent) is not listed here.
id_for() {
  local app="$1" file=""
  case "$2" in
    android) file="$app/android/app/build.gradle.kts" ;;
    ios)     file="$app/ios/Runner.xcodeproj/project.pbxproj" ;;
    macos)   file="$app/macos/Runner/Configs/AppInfo.xcconfig" ;;
    linux)   file="$app/linux/CMakeLists.txt" ;;
  esac
  [ -f "$file" ] || return 0
  # `|| true` on each: `set -o pipefail` above turns both "grep matched
  # nothing" and `head`'s SIGPIPE into a script-killing failure, and an id this
  # cannot read must reach the empty-string guard below rather than abort here.
  case "$2" in
    android) sed -n 's/.*applicationId *= *"\([^"]*\)".*/\1/p' "$file" | head -1 || true ;;
    # The test target's id is the app's plus `.RunnerTests`, so it is dropped
    # rather than counted as a second, colliding identity.
    ios)     { sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);.*/\1/p' "$file" \
               | grep -v '\.RunnerTests$' | sort -u | head -1; } || true ;;
    macos)   sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *\(.*[^ ]\) *$/\1/p' "$file" | head -1 || true ;;
    linux)   sed -n 's/.*set(APPLICATION_ID *"\([^"]*\)").*/\1/p' "$file" | head -1 || true ;;
  esac
}

for platform in android ios macos linux; do
  echo ""
  echo "=== $platform application id: one per codelab, and no two alike ==="
  pairs=""
  for pubspec in "${APPS[@]}"; do
    app="$(dirname "$pubspec")"
    codelab="$(echo "$app" | cut -d/ -f2)"
    id="$(id_for "$app" "$platform")"
    # Fail closed, the way discovery does above. A moved, renamed or reformatted
    # declaration must not read as "no collision found".
    if [ -z "$id" ]; then
      echo "::error::$app declares no $platform application id — the identity check cannot run"
      failed=1
      continue
    fi
    pairs="$pairs$codelab $id
"
  done

  # Property 1: a codelab whose steps disagree appears twice after `sort -u`.
  split="$(printf '%s' "$pairs" | sort -u | cut -d' ' -f1 | uniq -d)"
  if [ -n "$split" ]; then
    for codelab in $split; do
      echo "::error::$codelab does not share one $platform id across its steps:"
      printf '%s' "$pairs" | sort -u | grep "^$codelab " | sed 's/^/    /'
    done
    failed=1
  fi

  # Property 2: an id claimed by two codelabs appears twice with the codelab
  # column dropped.
  shared="$(printf '%s' "$pairs" | sort -u | awk '{print $2}' | sort | uniq -d)"
  if [ -n "$shared" ]; then
    for id in $shared; do
      echo "::error::$platform id $id is claimed by more than one codelab:"
      printf '%s' "$pairs" | sort -u | grep " $id\$" | sed 's/^/    /'
    done
    failed=1
  fi

  printf '%s' "$pairs" | sort -u | sed 's/^/  /'
done

exit "$failed"
