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

exit "$failed"
