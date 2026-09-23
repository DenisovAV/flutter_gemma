#!/usr/bin/env bash
# export_codelabs.sh — claat export, plus everything that must hold about its
# output before the result is allowed near a deploy.
#
# Called from website/deploy.sh, .github/workflows/firebase-hosting-merge.yml
# and .github/workflows/website-build-check.yml. All three used to carry their
# own copy of the export loop; that is why this file exists. The merge workflow
# deploys the live site and the build-check workflow is the PR gate, so a fix
# landed in deploy.sh alone was undone by the next merge, and a fix landed in
# both workflows was still never exercised before merge.
#
# WHY ANY OF THIS
#
# claat hardcodes https://storage.googleapis.com/claat-public/ for four scripts
# and the one stylesheet a codelab page has. That bucket began answering 403
# ("UserProjectAccountProblem — the billing account for the owning project is
# disabled in state absent"), and every published codelab lost its CSS *and* its
# JS: the <google-codelab-step> elements never upgrade and nothing hides the
# inactive ones, so all steps render stacked, unstyled, with no navigation.
#
# Nothing went red. The build was green, the deploy succeeded, the HTML was
# served. Only a human opening the page could tell. That is the failure mode
# this script exists to make impossible, which is why its checks are written as
# properties of the output rather than as the absence of yesterday's symptom:
#
#   * every resource a page loads is ours or explicitly allowed — NOT merely
#     "the string claat-public is gone". A claat upgrade that emitted a
#     different remote origin would sail through the second check and fail the
#     first, which is the whole point.
#   * every asset a page references exists — NOT merely "these five filenames
#     exist". A sixth asset under the same prefix would be rewritten to a URL
#     nobody serves, swapping a 403 for a 404.
#   * every vendored asset matches its recorded sha256 — existence is not
#     integrity; a truncated or emptied file passes a file test and breaks the
#     page exactly like the outage did.
#
# The page checks run in one python pass on purpose. `grep` as a predicate
# cannot distinguish "found nothing" from "could not read the file" — both are
# non-zero — so a guard built on it folds its own failure into the success
# branch. python either asserts, or raises; there is no third outcome.
#
# Two riders live here because they are the same edit:
#
#   * -ga "" blanks claat's default UA-49880327-14, the Google Codelabs team's
#     own Universal Analytics property. We were sending our readers' page views
#     to a third party, to a property dead since UA stopped processing data in
#     July 2023, and receiving nothing.
#   * the codelabs are added to sitemap.xml. `jaspr build --sitemap-domain` can
#     only enumerate Jaspr routes, and these are static claat output.
#
# Usage, from the website/ directory:
#   tool/export_codelabs.sh
#
#   CLAAT=/path/to/claat   override the binary (CI downloads a SHA-pinned one)
#   DOMAIN=https://…       sitemap origin; MUST match --sitemap-domain

set -euo pipefail

SRC_GLOB="codelabs/*/index.md"
OUT="build/jaspr/codelabs"
ASSET_DIR="build/jaspr/codelab-assets"
ASSET_PREFIX="/codelab-assets"
MANIFEST="web/codelab-assets/SHA256SUMS"
DEAD_PREFIX="https://storage.googleapis.com/claat-public/"
SITEMAP="build/jaspr/sitemap.xml"
DOMAIN="${DOMAIN:-https://fluttergemma.dev}"
CLAAT="${CLAAT:-$(command -v claat || echo "$HOME/.local/bin/claat")}"

# Remote origins a codelab page is allowed to reach. Both come from claat's own
# template, neither is ours, and both are the same shape of dependency as the
# bucket that broke — listed rather than ignored so that adding a third is a
# deliberate edit here and not something that slips in with a claat upgrade.
#   fonts.googleapis.com — Roboto / Source Code Pro / Material Icons
#   support.google.com   — the in-page feedback widget claat injects
ALLOWED_REMOTE="//fonts.googleapis.com/ //support.google.com/"

if [[ ! -x "$CLAAT" ]]; then
  echo "ERROR: claat not found (looked at '$CLAAT')." >&2
  echo "Install claat from https://github.com/googlecodelabs/tools/releases" >&2
  echo "or pass CLAAT=/path/to/claat." >&2
  exit 2
fi

echo "==> Exporting codelabs (claat static export)…"
mkdir -p "$OUT"
sources=0
for src in $SRC_GLOB; do
  [[ -e "$src" ]] || continue
  sources=$((sources + 1))
  # -ga "" — see the header. Do not drop it; claat's default is not empty.
  "$CLAAT" export -ga "" -o "$OUT" "$src"
done

# Not `mapfile`: macOS ships bash 3.2, which does not have it, and this script
# is run by hand there as often as it is by CI.
#
# ORDER IS LOAD-BEARING. On bash 3.2 under `set -u`, `${#pages[@]}` on an empty
# array is fine but `"${pages[@]}"` is a fatal "unbound variable" — and an empty
# list handed to grep makes it read stdin and hang. The count check below must
# stay ahead of every expansion of the array.
pages=()
while IFS= read -r page; do
  pages+=("$page")
done < <(find "$OUT" -mindepth 2 -name index.html | sort)

# A Firebase deploy is a full-site REPLACE (public=build/jaspr, no /codelabs
# rewrite), so shipping fewer codelabs than we have sources 404s the missing
# ones on the live site. Comparing against the source count rather than against
# zero also means a claat that exits 0 having written nothing for ONE input is
# caught — `set -e` only covers claat exiting non-zero.
#
# `-mindepth 2` is load-bearing: the catalogue route writes
# build/jaspr/codelabs/index.html itself, which would match at depth 1 and make
# this count wrong by one. Only claat writes <id>/index.html.
if [[ ${#pages[@]} -ne $sources ]]; then
  echo "ERROR: $sources codelab source(s) under $SRC_GLOB, but ${#pages[@]}" >&2
  echo "       page(s) under $OUT. Refusing to ship a partial set." >&2
  exit 1
fi
echo "    ${#pages[@]} codelab(s) exported"

echo "==> Repointing the element library at $ASSET_PREFIX/…"
# perl, not `sed -i`: the -i flag takes a mandatory argument on BSD/macOS and
# must NOT have one on GNU/Linux, and this script runs on both. perl exits 0
# even when it cannot open an input file, so this rewrite is not trusted — the
# verification pass below is what decides whether it worked.
perl -pi -e "s|\Q$DEAD_PREFIX\E|$ASSET_PREFIX/|g" "${pages[@]}"

echo "==> Verifying the exported pages…"
ASSET_DIR="$ASSET_DIR" ASSET_PREFIX="$ASSET_PREFIX" MANIFEST="$MANIFEST" \
ALLOWED_REMOTE="$ALLOWED_REMOTE" \
python3 - "${pages[@]}" <<'PY'
import hashlib, io, os, re, sys

asset_dir = os.environ["ASSET_DIR"]
prefix = os.environ["ASSET_PREFIX"] + "/"
manifest = os.environ["MANIFEST"]
allowed = tuple(os.environ["ALLOWED_REMOTE"].split())
pages = sys.argv[1:]

# <script src=…> and <link rel=stylesheet href=…> — everything the browser
# fetches and executes or applies. <img>/<a> are not in scope: they cannot run
# code, and claat writes its images next to the page.
SCRIPT = re.compile(r"<script\b[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"']", re.I)
STYLE = re.compile(
    r"<link\b(?=[^>]*\brel\s*=\s*[\"']stylesheet[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']",
    re.I,
)

foreign, referenced, ga = [], set(), []
for page in pages:
    # Read explicitly rather than letting a tool skip it: an unreadable page is
    # an error, never a page that passed.
    html = io.open(page, encoding="utf-8", errors="replace").read()
    for url in SCRIPT.findall(html) + STYLE.findall(html):
        if url.startswith(prefix):
            referenced.add(url[len(prefix):])
        elif not url.startswith(allowed):
            foreign.append((page, url))
    if re.search(r'gaid\s*=\s*[\"\']UA-', html, re.I):
        ga.append(page)

fail = False

if foreign:
    print("  [FAIL] pages load a resource that is neither ours nor allowed:")
    for page, url in foreign:
        print(f"         {page}\n           -> {url}")
    print("         Either vendor it under web/codelab-assets/ and extend the")
    print("         rewrite, or add its origin to ALLOWED_REMOTE on purpose.")
    fail = True

if ga:
    print("  [FAIL] pages still carry a Universal Analytics id:")
    for page in ga:
        print(f"         {page}")
    print("         claat ignored -ga \"\"; check its version.")
    fail = True

# Derived from the pages, not hardcoded: whatever they reference is what has to
# exist, so a sixth asset cannot be rewritten into a URL nobody serves.
if not referenced:
    print(f"  [FAIL] no page references anything under {prefix} — the rewrite")
    print("         did not take effect (claat's template changed?).")
    fail = True

want = {}
if os.path.exists(manifest):
    for line in io.open(manifest, encoding="utf-8"):
        line = line.strip()
        if line:
            digest, name = line.split(None, 1)
            want[name.strip()] = digest
else:
    print(f"  [FAIL] {manifest} is missing — nothing pins the vendored bytes.")
    fail = True

for name in sorted(referenced):
    path = os.path.join(asset_dir, name)
    if not os.path.exists(path):
        print(f"  [FAIL] {name} is referenced but absent from {asset_dir}/")
        fail = True
        continue
    # Existence is not integrity. A truncated or emptied file passes a file
    # test and breaks the page exactly the way the outage did.
    got = hashlib.sha256(io.open(path, "rb").read()).hexdigest()
    if name not in want:
        print(f"  [FAIL] {name} is served but not listed in {manifest}")
        fail = True
    elif want[name] != got:
        print(f"  [FAIL] {name} does not match {manifest}")
        print(f"         expected {want[name]}\n         got      {got}")
        fail = True

if fail:
    sys.exit(1)
print(f"    {len(pages)} page(s), {len(referenced)} vendored asset(s), "
      f"sha256 verified, no unexpected origin")
PY

echo "==> Adding codelabs to sitemap.xml…"
if [[ ! -f "$SITEMAP" ]]; then
  echo 'ERROR: sitemap.xml not found — run "jaspr build --sitemap-domain" first.' >&2
  exit 1
fi
DOMAIN="$DOMAIN" python3 - "$SITEMAP" "${pages[@]}" <<'PY'
import io, os, re, sys
from urllib.parse import quote
from xml.sax.saxutils import escape

sitemap, pages = sys.argv[1], sys.argv[2:]
domain = os.environ["DOMAIN"].rstrip("/")
xml = io.open(sitemap, encoding="utf-8").read()

# str.replace on an absent token is a no-op that would still let this step
# print a success line naming entries it never inserted.
if "</urlset>" not in xml:
    sys.exit(f"ERROR: {sitemap} has no </urlset> — jaspr's template changed, or "
             "the file was written partially. Refusing to guess where to append.")

# DOMAIN is documented as having to match --sitemap-domain and was never
# checked. A mismatch yields a sitemap listing two different sites.
origins = {m.group(1) for m in re.finditer(r"<loc>(https?://[^/<]+)", xml)}
if origins and domain not in origins:
    sys.exit(f"ERROR: DOMAIN is {domain} but the sitemap already lists "
             f"{', '.join(sorted(origins))} — pass the same --sitemap-domain.")

before = xml.count("<loc>")
m = re.search(r"<lastmod>([^<]+)</lastmod>", xml)
lastmod = m.group(1) if m else ""

entries = []
for page in pages:
    slug = os.path.basename(os.path.dirname(page))
    # firebase.json runs cleanUrls with trailingSlash:false, so a slashed URL
    # 301s and a sitemap full of redirects is one Search Console complains about.
    loc = escape(f"{domain}/codelabs/{quote(slug)}")
    # Match the whole element, not the substring: `…/codelabs/foo` occurs inside
    # `…/codelabs/foo-bar`, which would silently skip a legitimate new codelab.
    if f"<loc>{loc}</loc>" in xml:
        continue
    lm = f"\n    <lastmod>{escape(lastmod)}</lastmod>" if lastmod else ""
    entries.append(
        f"  <url>\n    <loc>{loc}</loc>{lm}\n    <priority>0.5</priority>\n  </url>\n"
    )

if entries:
    xml = xml.replace("</urlset>", "".join(entries) + "</urlset>")
    io.open(sitemap, "w", encoding="utf-8").write(xml)

# Count what landed rather than what was intended.
after = io.open(sitemap, encoding="utf-8").read().count("<loc>")
if after != before + len(entries):
    sys.exit(f"ERROR: expected {before + len(entries)} <loc> entries after the "
             f"write, found {after}.")
print(f"    {len(entries)} codelab URL(s) added, {after} total")
PY
