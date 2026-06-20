#!/usr/bin/env bash
# Build + deploy the flutter_gemma website to Firebase Hosting.
#
# Ships two artifacts on one hosting site:
#   /            + /docs/*   -> Jaspr static site (this package)
#   /try/...                 -> the Flutter web example app (live demo)
#
# Usage:  ./deploy.sh            (build both + deploy)
#         ./deploy.sh --no-example   (skip rebuilding the example app)
set -euo pipefail

WEBSITE_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE_DIR="$WEBSITE_DIR/../packages/flutter_gemma/example"
DOMAIN="https://fluttergemma.dev"
PROJECT="aichat-c0c27"
TARGET="fluttergemma"

cd "$WEBSITE_DIR"

# Free jaspr's dev ports so the build's transient server can bind.
for p in 5567 8080 8181 5467; do
  lsof -ti ":$p" 2>/dev/null | xargs kill -9 2>/dev/null || true
done

echo "==> Building Jaspr site (SSG)…"
jaspr build --sitemap-domain "$DOMAIN"

if [[ "${1:-}" != "--no-example" ]]; then
  echo "==> Building Flutter web example app (base-href /try/)…"
  ( cd "$EXAMPLE_DIR" && flutter build web --release --base-href /try/ )
fi

echo "==> Assembling /try into the Jaspr build output…"
rm -rf build/jaspr/try
mkdir -p build/jaspr/try
cp -R "$EXAMPLE_DIR/build/web/." build/jaspr/try/

echo "==> Deploying to Firebase Hosting ($TARGET)…"
firebase deploy --only "hosting:$TARGET" --project "$PROJECT"

echo "==> Done. https://fluttergemma.web.app  (live demo at /try)"
