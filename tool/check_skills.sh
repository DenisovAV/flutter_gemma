#!/usr/bin/env bash
#
# Every API symbol the shipped agent skills name must still exist in the
# workspace sources.
#
# Skills under packages/flutter_gemma/skills/ are read by a MACHINE, not a
# person. A renamed symbol does not make them look odd — it makes them
# confidently wrong, and the user's agent writes code against an API that is
# gone. Nothing else in the build notices: skills are markdown, so analyze,
# test and format all stay green.
#
# Three shapes are checked, because between them they cover where API names
# actually appear in a SKILL.md:
#
#   inline `backticked` identifiers      CamelCase, or camelCase with a capital
#   named arguments in ```dart fences    maxOutputTokens:
#   dotted members in ```dart fences     TaskType.retrievalQuery
#
# The first shape alone is not enough — it misses `maxOutputTokens` entirely,
# because that symbol appears in the skills only inside code blocks. Verified by
# mutation: renaming maxOutputTokens, supportsFunctionCalls,
# TaskType.retrievalQuery, BuiltInAi.availability or Message.toolResponse each
# turns this script red.
#
# What it CANNOT catch: a symbol that still exists but changed meaning. The STT
# language went from a load-time property to a per-transcription one without a
# single rename — for that class, read the skill.
#
# Usage, from the repo root:
#   bash tool/check_skills.sh
# Exit 1 means a skill names something that no longer exists.

set -uo pipefail

SKILLS_DIR=packages/flutter_gemma/skills

if [ ! -d "$SKILLS_DIR" ]; then
  echo "no skills directory at $SKILLS_DIR — run from the repo root" >&2
  exit 2
fi

LIB=$(mktemp)
trap 'rm -f "$LIB"' EXIT
find packages -path '*/lib/*' -name '*.dart' -not -path '*/build/*' \
  -exec cat {} + > "$LIB" 2>/dev/null

if [ ! -s "$LIB" ]; then
  echo "collected no Dart sources — the check would pass vacuously" >&2
  exit 2
fi

# Not Dart API: build-config keys and prose that survives the shape filter.
SKIP=' minSdk platform dependencies '

total=0
missing=0

for f in "$SKILLS_DIR"/*/SKILL.md; do
  skill=$(basename "$(dirname "$f")")
  code=$(awk '/^```dart/{c=1;next} /^```/{c=0} c' "$f")

  inline=$(grep -oE '`[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*`' "$f" \
    | tr -d '`' | grep -E '^[A-Z]|[a-z][A-Z]')
  named=$(printf '%s' "$code" \
    | grep -oE '(^|[ (,])[a-z][A-Za-z0-9_]*:' | tr -d ' (,:')
  dotted=$(printf '%s' "$code" \
    | grep -oE '\b[A-Z][A-Za-z0-9_]*\.[a-z][A-Za-z0-9_]*')

  for sym in $(printf '%s\n%s\n%s\n' "$inline" "$named" "$dotted" | sort -u); do
    [ -z "$sym" ] && continue
    case "$SKIP" in *" $sym "*) continue ;; esac

    total=$((total + 1))
    base="${sym%%.*}"
    leaf="${sym##*.}"

    if ! grep -q "\b${base}\b" "$LIB"; then
      echo "  MISSING  ${sym}   (${skill})"
      missing=$((missing + 1))
    elif [ "$base" != "$leaf" ] && ! grep -q "\b${leaf}\b" "$LIB"; then
      echo "  MISSING  ${sym}   (${skill})"
      missing=$((missing + 1))
    fi
  done
done

skills_count=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "checked ${total} symbol(s) across ${skills_count} skill(s), ${missing} missing"

# A run that examined nothing is indistinguishable from a clean run — refuse to
# report success in that case.
if [ "$total" -eq 0 ]; then
  echo "extracted no symbols — the check is broken, not the skills" >&2
  exit 2
fi

[ "$missing" -eq 0 ] || exit 1
