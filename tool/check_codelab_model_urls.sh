#!/usr/bin/env bash
#
# Every model URL a codelab pins, still resolving.
#
# The codelabs pin an exact file in an exact Hugging Face repo. Those are
# community repos: a rename or a re-upload under a new filename breaks the very
# first step of a codelab, and nothing in the build would notice — `flutter
# analyze` type-checks a string literal, it does not fetch it.
#
# Run nightly, not on every push: it is the one check here that depends on a
# third party being up, and a transient 5xx must not turn someone's PR red.
set -euo pipefail
cd "$(dirname "$0")/.."

# Dart concatenates adjacent string literals, and these URLs are written
# across two lines to stay inside the line limit — so a line-oriented grep sees
# neither half. Join the literals first, then match.
urls=$(python3 - <<'EXTRACT'
import pathlib, re
found = set()
for f in pathlib.Path('codelabs').glob('*/*/lib/*.dart'):
    text = f.read_text()
    # collapse adjacent 'a' 'b' literals into one string
    joined = re.sub(r"'\s*\n\s*'", "", text)
    found.update(re.findall(r"https://huggingface\.co/[^'\s]+?\.(?:litertlm|task)", joined))
print("\n".join(sorted(found)))
EXTRACT
)

if [ -z "$urls" ]; then
  echo "::error::no model URLs found under codelabs/ — discovery is broken"
  exit 1
fi

echo "Checking $(printf '%s\n' "$urls" | wc -l | tr -d ' ') model URL(s)."
failed=0
while IFS= read -r url; do
  [ -z "$url" ] && continue
  # 200 = public. 401/403 = the file is there, the repo is licence-gated (the
  # Getting Started model is). 404 = renamed or gone, which is the case worth
  # waking someone for.
  code=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 30 "$url" || echo "000")
  case "$code" in
    200|401|403) printf '  ok   %s  %s\n' "$code" "$url" ;;
    *)           printf '  FAIL %s  %s\n' "$code" "$url"
                 echo "::error::model URL not resolving ($code): $url"
                 failed=1 ;;
  esac
done <<< "$urls"

exit "$failed"
