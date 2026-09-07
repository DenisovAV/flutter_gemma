# Step 4 — fine-tune the model on these tools

Not a Flutter app. This directory holds the two inputs a
[litetune](https://github.com/DenisovAV/litetune) run needs, for the three
tools the rest of this codelab declares:

```text
tools.json    the three declarations, the same ones lib/tools.dart holds
raw.jsonl     72 prompt -> tool-call rows to train and score on
```

`tool/check_codelabs.sh` discovers step apps by their `pubspec.yaml`. There is
none here on purpose, so this directory is not analyzed, tested or built — it
is data and commands.

## What you need

`pip install litetune` — **Linux or macOS**, Python 3.10–3.12. Python 3.13
runs `prepare`, `tune` and `bundle` but not `convert` or `verify`, because the
export toolchain pins `numpy==2.0.2` and that stops publishing wheels after
3.12. Windows is untried. On Linux also `sudo apt-get install -y libvulkan1`,
or every invocation — `--help` included — dies in under a second.

It runs on CPU, which is workable at 270M. The stage environments are cached
and they are large: `convert` pulls ~1.6 GB, `tune` 588 MB. `litetune env`
shows what is on disk and `litetune env --clean` removes it.

This is alpha software, and its alpha is stated as *measured end to end on
`google/functiongemma-270m-it` and function calling* — which is exactly the
model and the task this codelab is on. The other scorer and the other base
models it supports are outside what has been measured.

**You can skip this step.** The app in `complete/` works on the stock
FunctionGemma and on Gemma 4 without any of it.

## The five commands

Run them from this directory. Each is separate because each fails differently.

```bash
# 1. Split, and reject rows that cannot be scored. Seconds.
litetune prepare --data raw.jsonl --output-dir data --context-length 1024 \
                 --tokenizer google/functiongemma-270m-it

# 2. Fine-tune. CPU is fine at this size.
litetune tune --model google/functiongemma-270m-it --data data/train.jsonl \
              --output-dir tuned --prompt-mode prerendered --method lora

# 3. Convert, sweeping recipes rather than trusting a default.
litetune convert --model tuned/model --output-dir artifacts \
                 --recipe dynamic_wi8_afp32 --recipe weight_only_wi8_afp32

# 4. Measure what the conversion cost, against the float twin.
#    `convert` names the artifact; look the filename up rather than build it.
litetune verify --model artifacts/weight_only_wi8_afp32/<name>.litertlm \
                --reference tuned/model --data data/heldout.jsonl \
                --json > manifest.json

# 5. Package the artifact with what was measured about it.
litetune bundle --output-dir bundle \
                --model artifacts/weight_only_wi8_afp32/<name>.litertlm \
                --declarations tools.json --prompt-mode prerendered \
                --base-model google/functiongemma-270m-it \
                --base-model-revision <commit-sha> \
                --adapter tuned/adapter \
                --train-metrics tuned/metrics.json \
                --verify-manifest manifest.json
```

`--prompt-mode prerendered` because that is what this app does: `InferenceChat`
renders the declarations into the prompt itself for `ModelType.functionGemma`.
The value must be the **same** in `tune` and `bundle`; the wrong one produces a
fluent wrong answer rather than an error.

`--recipe` has no default, and litetune's own line for why is worth keeping:
*"A sweep of one is not a comparison."*

## Then open it in the app

Step 3 already gives you a `.litertlm` per recipe under `artifacts/<recipe>/`.
Run `complete/`, choose **Open a .litertlm from disk**, and paste the absolute
path. Nothing in `lib/` changes — it is a `.litertlm`, and the app opens it the
way it opens the two it downloads.

## About these 72 rows

They are enough to run all five commands end to end and get a file out. They
are not enough to move a quality number: litetune's own published figures come
from thousands of examples, and half of these are held out for scoring. Treat
the run as a rehearsal of the pipeline, and bring your own data when you want
a result.
