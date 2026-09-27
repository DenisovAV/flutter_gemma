#!/usr/bin/env bash
# vendor_codelab_assets.sh — (re)fetch everything a codelab page loads, so that
# it loads nothing from anybody else.
#
# Run by hand, not by the build. Its output is committed; the build only
# verifies it, via the SHA256SUMS this script writes and the allowlist in
# export_codelabs.sh.
#
# WHY A SCRIPT AND NOT A ONE-OFF
#
# The five element-library files were first recovered by hand from a Wayback
# snapshot, after the bucket claat points at started answering 403. That worked
# once and left nobody able to update them safely. Everything here is fetched
# from a named package at a named version instead, so the next person can rerun
# it, diff the result, and know what changed.
#
# The npm sources are not a guess: every file was hash-matched against them
# during review of #538. Rerunning this script over the committed files must
# leave SHA256SUMS unchanged.
#
#   codelab-elements@1.0.1            codelab-elements.js, codelab-elements.css
#   @webcomponents/custom-elements@1.3.0   custom-elements.min.js, native-shim.js
#   code-prettify@0.1.0               loader/prettify.js
#
# FONTS
#
# claat's template links fonts.googleapis.com twice. Every page view therefore
# handed Google the reader's IP, User-Agent and referrer before a single glyph
# was drawn — the kind of thing a Munich court has already fined a site over,
# and pointless here because the fonts are Apache-2.0 and OFL and may simply be
# served from our own origin.
#
# Only the latin and latin-ext subsets are taken. Google splits these families
# across cyrillic, greek, vietnamese, math and symbol ranges as well; carrying
# all of them costs 1.4 MB instead of 316 KB, and the codelabs are English. A
# page that one day needs Cyrillic will fall back to a system font for those
# glyphs — visible, harmless, and fixed by widening SUBSETS below.

set -euo pipefail

cd "$(dirname "$0")/.."          # website/
DEST="web/codelab-assets"
FONT_DIR="$DEST/fonts"
SUBSETS="latin latin-ext"

# A modern UA is required: Google serves woff2 + unicode-range to browsers it
# recognises and a single fat truetype file to everything else.
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"

FAMILIES="Source+Code+Pro:400|Roboto:400,300,400italic,500,700|Roboto+Mono"

mkdir -p "$FONT_DIR"

echo "==> Element library"
fetch() {  # <url> <dest>
  curl -fsSL --retry 3 --max-time 120 -o "$2" "$1"
  printf '    %-24s %8s bytes\n' "$(basename "$2")" "$(wc -c < "$2" | tr -d ' ')"
}
fetch "https://cdn.jsdelivr.net/npm/codelab-elements@1.0.1/codelab-elements.js" \
      "$DEST/codelab-elements.js"
fetch "https://cdn.jsdelivr.net/npm/codelab-elements@1.0.1/codelab-elements.css" \
      "$DEST/codelab-elements.css"
fetch "https://cdn.jsdelivr.net/npm/@webcomponents/custom-elements@1.3.0/custom-elements.min.js" \
      "$DEST/custom-elements.min.js"
fetch "https://cdn.jsdelivr.net/npm/@webcomponents/custom-elements@1.3.0/src/native-shim.js" \
      "$DEST/native-shim.js"
fetch "https://cdn.jsdelivr.net/npm/code-prettify@0.1.0/loader/prettify.js" \
      "$DEST/prettify.js"

echo "==> Fonts"
curl -fsSL --retry 3 --max-time 60 -A "$UA" \
     "https://fonts.googleapis.com/css?family=$FAMILIES" -o /tmp/cl_fonts.css
curl -fsSL --retry 3 --max-time 60 -A "$UA" \
     "https://fonts.googleapis.com/icon?family=Material+Icons" -o /tmp/cl_icons.css

SUBSETS="$SUBSETS" FONT_DIR="$FONT_DIR" DEST="$DEST" python3 - <<'PY'
import io, os, re, subprocess, sys

subsets = set(os.environ["SUBSETS"].split())
font_dir, dest = os.environ["FONT_DIR"], os.environ["DEST"]

def grab(url, name):
    path = os.path.join(font_dir, name)
    subprocess.run(["curl", "-fsSL", "--retry", "3", "--max-time", "60",
                    "-o", path, url], check=True)
    return os.path.getsize(path)

out, total, kept = [], 0, 0

# Families: keep only the subsets we serve, and give each file a name that says
# what it is instead of Google's opaque hash.
css = io.open("/tmp/cl_fonts.css", encoding="utf-8").read()
for part in re.split(r"(?=/\*\s*[a-z-]+\s*\*/)", css):
    m = re.match(r"/\*\s*([a-z-]+)\s*\*/", part.strip())
    if not m or m.group(1) not in subsets:
        continue
    sub = m.group(1)
    fam = re.search(r"font-family:\s*'([^']+)'", part).group(1)
    weight = re.search(r"font-weight:\s*(\d+)", part).group(1)
    style = re.search(r"font-style:\s*(\w+)", part).group(1)
    url = re.search(r"url\((https://[^)]+)\)", part).group(1)
    name = f"{fam.lower().replace(' ', '-')}-{weight}{'i' if style == 'italic' else ''}-{sub}.woff2"
    total += grab(url, name)
    kept += 1
    out.append(re.sub(r"url\(https://[^)]+\)", f"url(fonts/{name})", part).rstrip() + "\n")

# Material Icons: one file, plus the .material-icons class the template needs.
icons = io.open("/tmp/cl_icons.css", encoding="utf-8").read()
url = re.search(r"url\((https://[^)]+)\)", icons).group(1)
total += grab(url, "material-icons.woff2")
kept += 1
out.append(re.sub(r"url\(https://[^)]+\)", "url(fonts/material-icons.woff2)", icons))

header = (
    "/* Generated by tool/vendor_codelab_assets.sh — do not edit.\n"
    " *\n"
    " * Replaces claat's two fonts.googleapis.com <link>s so a codelab page\n"
    " * loads nothing from a third party. Roboto and Roboto Mono are Apache-2.0,\n"
    " * Source Code Pro and Material Icons are OFL/Apache-2.0; self-hosting is\n"
    f" * what those licences are for. Subsets: {', '.join(sorted(subsets))}.\n"
    " */\n"
)
io.open(os.path.join(dest, "codelab-fonts.css"), "w", encoding="utf-8").write(
    header + "".join(out))
print(f"    {kept} font file(s), {total // 1024} KB")
PY

echo "==> SHA256SUMS"
( cd "$DEST" && find . -type f ! -name SHA256SUMS -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 \
    | sed 's| \./| |' > SHA256SUMS )
echo "    $(wc -l < "$DEST/SHA256SUMS" | tr -d ' ') file(s) pinned"
echo
echo "Now run tool/export_codelabs.sh and commit both if it passes."
