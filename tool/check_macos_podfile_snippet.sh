#!/bin/sh
#
# The macOS `post_install` snippet lives in five places: three example Podfiles,
# the core README (which is the pub.dev landing page users copy from) and the
# website. They must stay byte-identical.
#
# This is not tidiness. The snippet is frozen into every app's project.pbxproj
# at `pod install` time, and upgrading flutter_gemma_litertlm does NOT re-run
# `pod install` — the package declares no macOS plugin, so Flutter's tracked
# plugin set never changes. A fix that lands in one copy therefore never reaches
# users who copied another. When this check was written the five copies had
# already drifted into three vintages: the genkit example predated all three of
# the #300/#368 fixes, and the README copy — the one users actually paste — was
# missing `input_paths`, i.e. every app built from it carried the #368
# incremental-build bug.
#
# Usage: tool/check_macos_podfile_snippet.sh   (exit 1 on drift)

set -e
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -f "$work"/* 2>/dev/null; rmdir "$work" 2>/dev/null' EXIT

# Podfiles: the block runs from `post_install` to end of file.
for f in packages/flutter_gemma/example/macos/Podfile \
         packages/genkit_flutter_gemma/example/macos/Podfile \
         packages/flutter_gemma_speech/example/macos/Podfile; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f" >&2
    exit 1
  fi
  awk '/^post_install do \|installer\|/{p=1} p' "$f" \
    > "$work/$(echo "$f" | tr '/' '%')"
done

# Markdown: the block is inside a fenced code block (```ruby in the README,
# a plain ``` on the website — the site's highlighter only knows Dart).
extract_fenced() {
  awk '
    /^```/ && p { exit }
    p { print }
    /^```/ && !p { fence = 1; next }
    fence && /^post_install do \|installer\|/ { p = 1; print; next }
    { fence = 0 }
  ' "$1"
}
for f in packages/flutter_gemma/README.md website/content/docs/desktop.md; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f" >&2
    exit 1
  fi
  extract_fenced "$f" > "$work/$(echo "$f" | tr '/' '%')"
done

# Every extraction must have found something — an empty file would make all
# five "match" and turn this check into one that cannot fail.
for f in "$work"/*; do
  if [ ! -s "$f" ]; then
    echo "EMPTY extraction: $(basename "$f" | tr '%' '/')" >&2
    echo "  The snippet was not found where this script expects it." >&2
    exit 1
  fi
done

count=$(shasum -a 256 "$work"/* | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
if [ "$count" -ne 1 ]; then
  echo "macOS post_install snippet has drifted across its copies:" >&2
  for f in "$work"/*; do
    printf '  %s  %s\n' \
      "$(shasum -a 256 "$f" | cut -c1-16)" \
      "$(basename "$f" | tr '%' '/')" >&2
  done
  echo "  Make every copy identical to packages/flutter_gemma/example/macos/Podfile." >&2
  exit 1
fi

echo "macOS post_install snippet: 5 copies, all identical."
