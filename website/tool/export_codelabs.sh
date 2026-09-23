#!/usr/bin/env bash
# export_codelabs.sh — claat export, plus the three things that must be applied
# to its output every single time.
#
# Called from BOTH website/deploy.sh and .github/workflows/firebase-hosting-merge.yml.
# Those two used to carry their own copy of the export loop. That duplication is
# the reason this file exists: CI deploys the live site, so a fix landed in
# deploy.sh alone would be silently undone by the next merge.
#
# What it does beyond running claat:
#
#   1. Points the exported HTML at our own copy of the codelab element library.
#      claat hardcodes https://storage.googleapis.com/claat-public/ for four
#      scripts and the stylesheet. That bucket began returning HTTP 403
#      ("UserProjectAccountProblem — the billing account ... is disabled in state
#      absent") and every published codelab lost its CSS *and* its JS: the
#      <google-codelab-step> custom elements never upgrade and nothing hides the
#      inactive steps, so all steps render stacked and unstyled, with no
#      navigation and no syntax highlighting. The five files are vendored in
#      web/codelab-assets/ — recovered from the Wayback snapshot of that bucket
#      and verified byte-identical to npm codelab-elements@1.0.1.
#
#      All five are load-bearing, none is legacy: codelab-elements.js is
#      Closure-compiled to ES5, so its custom-element constructors are plain
#      functions, which native customElements.define rejects — that is exactly
#      what native-shim.js patches. prettify.js backs the two prettyPrintOne
#      calls inside the bundle.
#
#   2. Blanks the Google Analytics id. Without -ga, claat stamps in its default
#      UA-49880327-14 — the Google Codelabs team's own Universal Analytics
#      property. We were sending our readers' page views to a third party's dead
#      UA property (UA stopped processing data in July 2023) and receiving
#      nothing ourselves.
#
#   3. Adds the codelabs to sitemap.xml. `jaspr build --sitemap-domain` can only
#      enumerate Jaspr routes, and the codelab pages are static claat output, so
#      the sitemap advertised the /codelabs catalogue and nothing under it.
#
# Usage, from the website/ directory:
#   tool/export_codelabs.sh
#
#   CLAAT=/path/to/claat   override the binary (CI downloads a SHA-pinned one)
#   DOMAIN=https://…       sitemap origin; MUST match --sitemap-domain

set -euo pipefail

OUT="build/jaspr/codelabs"
ASSET_PREFIX="/codelab-assets"
DEAD_PREFIX="https://storage.googleapis.com/claat-public/"
DOMAIN="${DOMAIN:-https://fluttergemma.dev}"
CLAAT="${CLAAT:-$(command -v claat || echo "$HOME/.local/bin/claat")}"

if [[ ! -x "$CLAAT" ]]; then
  echo "ERROR: claat not found (looked at '$CLAAT')." >&2
  echo "Install claat from https://github.com/googlecodelabs/tools/releases" >&2
  echo "or pass CLAAT=/path/to/claat." >&2
  exit 2
fi

echo "==> Exporting codelabs (claat static export)…"
mkdir -p "$OUT"
for src in codelabs/*/index.md; do
  [[ -e "$src" ]] || continue
  # -ga "" — see (2) above. Do not drop this flag; the default is not empty.
  "$CLAAT" export -ga "" -o "$OUT" "$src"
done

# A Firebase deploy is a full-site REPLACE (public=build/jaspr, no /codelabs
# rewrite), so "no HTML produced" — empty glob, wrong cwd, or claat emitting
# nothing — would silently 404 the live codelabs. Fail instead.
# `-mindepth 2` is load-bearing: the catalogue route writes
# build/jaspr/codelabs/index.html itself, which would match at depth 1 and make
# this guard pass on zero codelabs. Only claat writes <id>/index.html.
# Not `mapfile`: macOS ships bash 3.2, which does not have it, and this script
# is run by hand there as often as it is by CI.
pages=()
while IFS= read -r page; do
  pages+=("$page")
done < <(find "$OUT" -mindepth 2 -name index.html | sort)
if [[ ${#pages[@]} -eq 0 ]]; then
  echo "ERROR: no codelab HTML produced under $OUT." >&2
  exit 1
fi
echo "    ${#pages[@]} codelab(s) exported"

echo "==> Repointing the element library at $ASSET_PREFIX/…"
# The vendored files are copied into the build output by `jaspr build` (web/ is
# Jaspr's static directory). If they are missing, rewriting the URLs would swap
# a 403 for a 404 — still broken, but harder to notice. Check first.
missing=0
for f in codelab-elements.js codelab-elements.css native-shim.js \
         custom-elements.min.js prettify.js; do
  [[ -f "build/jaspr${ASSET_PREFIX}/$f" ]] || { echo "    missing: $f"; missing=1; }
done
if [[ $missing -eq 1 ]]; then
  echo "ERROR: build/jaspr${ASSET_PREFIX}/ is incomplete — did jaspr build run," >&2
  echo "       and does web/codelab-assets/ still hold all five files?" >&2
  exit 1
fi

# perl, not `sed -i`: the -i flag takes a mandatory argument on BSD/macOS and
# must NOT have one on GNU/Linux, and this script runs on both.
perl -pi -e "s|\Q$DEAD_PREFIX\E|$ASSET_PREFIX/|g" "${pages[@]}"

# Verify rather than assume. A claat upgrade could start emitting a different
# spelling of the same URL, and the failure mode is a live site that looks fine
# in the build log and broken in the browser.
if grep -l "storage.googleapis.com/claat-public" "${pages[@]}" 2>/dev/null; then
  echo "ERROR: the files above still reference the dead claat-public bucket." >&2
  echo "       claat's template changed; update DEAD_PREFIX." >&2
  exit 1
fi
if grep -l 'gaid="UA-' "${pages[@]}" 2>/dev/null; then
  echo "ERROR: the files above still carry a Universal Analytics id." >&2
  echo "       claat ignored -ga; check its version." >&2
  exit 1
fi

echo "==> Adding codelabs to sitemap.xml…"
SITEMAP="build/jaspr/sitemap.xml"
if [[ ! -f "$SITEMAP" ]]; then
  echo 'ERROR: sitemap.xml not found — run "jaspr build --sitemap-domain" first.' >&2
  exit 1
fi
DOMAIN="$DOMAIN" python3 - "$SITEMAP" "${pages[@]}" <<'PY'
import io, os, re, sys

sitemap, pages = sys.argv[1], sys.argv[2:]
domain = os.environ["DOMAIN"].rstrip("/")
xml = io.open(sitemap, encoding="utf-8").read()

# Reuse the timestamp jaspr already wrote, so every entry agrees.
m = re.search(r"<lastmod>([^<]+)</lastmod>", xml)
lastmod = m.group(1) if m else ""

# firebase.json runs cleanUrls with trailingSlash:false, so a slashed URL 301s.
# A sitemap full of redirects is a sitemap Search Console complains about.
entries = []
for p in pages:
    slug = os.path.basename(os.path.dirname(p))
    loc = f"{domain}/codelabs/{slug}"
    if loc in xml:
        continue
    lm = f"\n    <lastmod>{lastmod}</lastmod>" if lastmod else ""
    entries.append(f"  <url>\n    <loc>{loc}</loc>{lm}\n    <priority>0.5</priority>\n  </url>\n")

if entries:
    xml = xml.replace("</urlset>", "".join(entries) + "</urlset>")
    io.open(sitemap, "w", encoding="utf-8").write(xml)
print(f"    {len(entries)} codelab URL(s) added, {xml.count('<loc>')} total")
PY
