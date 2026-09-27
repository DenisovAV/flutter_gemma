#!/usr/bin/env bash
# Warns — never fails — when a codelab's copy of the LiteRT web bundle differs
# from this repo's packages/flutter_gemma_litertlm/web/.
#
# Why only a warning: the codelab step apps depend on the PUBLISHED package, and
# tool/check_codelabs.sh compares their copies against the version each app
# resolves. Between the PR that rebuilds the bundle and the publish, the copies
# must still match the OLD, published bundle — syncing them early would turn
# that check red, correctly. The moment to sync is after the publish (release
# skill, Step 10b). This makes the consequence visible on the PR that causes it
# instead of as a red Codelabs run after the release (#562).
set -euo pipefail
src=packages/flutter_gemma_litertlm/web
checked=0
differing=0
while IFS= read -r copy; do
  name=$(basename "$copy")
  [ -f "$src/$name" ] || continue
  checked=$((checked + 1))
  if ! cmp -s "$copy" "$src/$name"; then
    echo "::warning file=$copy::differs from $src/$name — after publishing flutter_gemma_litertlm, sync this copy (release skill Step 10b)"
    differing=$((differing + 1))
  fi
done < <(find codelabs -path '*/web/*.js' -not -path '*/build/*' | sort)
# Fail closed on the one thing that means the check is broken, not the copies:
# finding nothing to compare reads as "all in sync" otherwise.
if [ "$checked" -eq 0 ]; then
  echo "::error::no codelab copy of a $src file found — the check compared nothing"
  exit 1
fi
echo "codelab web copies checked: $checked, differing from $src: $differing"
