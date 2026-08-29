# Shipped-manifest fixtures

Snapshots of every live `litertlm_manifest.json` the
[hf-to-litertlm](https://github.com/john-rocky/hf-to-litertlm) converter had
shipped as of 2026-08-27 — 21 repos, 35 variants. The regression sweep in
`../shipped_manifests_regression_test.dart` runs the resolver over all of them,
so the resolver is tested against the real published data, not just synthetic
shapes.

Regenerate (the dataset-shape counts in the sweep test then need updating):

```sh
for repo in $(ls *.json | sed 's/__/\//; s/\.json//'); do
  curl -sL "https://huggingface.co/$repo/resolve/main/litertlm_manifest.json" \
    -o "$(echo "$repo" | sed 's/\//__/').json"
done
```
