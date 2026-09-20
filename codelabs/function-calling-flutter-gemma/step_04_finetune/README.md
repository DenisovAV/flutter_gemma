# Step 4 — fine-tune the model on these tools

Not a Flutter app. This directory holds the two inputs a
[litetune](https://github.com/DenisovAV/litetune) run needs, for the four
tools the rest of this codelab declares:

```text
tools.json    the four declarations, the same ones lib/tools.dart holds
raw.jsonl     90 prompt -> tool-call rows to train and score on
```

Written for **litetune 0.1.7**, which is the first release that trains and
scores a model the way the runtime calls it. Earlier versions trained the call
as plain text, and a model tuned by one of them answers an application with
something the runtime does not read back as a call at all.

`tool/check_codelabs.sh` discovers step apps by their `pubspec.yaml`. There is
none here on purpose, so this directory is not analyzed, tested or built — it
is data and commands.

## What you need

**Access to the base model, requested before you start.** Three of the five
commands below name `google/functiongemma-270m-it`, and that repository is
gated with **manual** approval — an anonymous fetch of its `config.json`
returns `401`, and a person grants access rather than a checkbox, so it can
take hours or days. Request it on
[the model page](https://huggingface.co/google/functiongemma-270m-it), then
`hf auth login` (or export `HF_TOKEN`) once it is granted. Without it command 1
fails on the tokenizer download and you never reach command 2. Nothing else in
this codelab needs a token: the `.litertlm` the app downloads comes from the
ungated `sasha-denisov/function-gemma-270M-it`.

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
                 --tokenizer google/functiongemma-270m-it \
                 --base-model google/functiongemma-270m-it \
                 --declarations tools.json

# 2. Fine-tune. One epoch at 1e-5 — a twentieth of the default rate — because
#    72 rows that are all tool calls will happily eat the rest of the model;
#    see "The dial you are turning" below. On a CPU add --dtype float32:
#    bfloat16 has no hardware behind it there and ran 165x slower.
litetune tune --model google/functiongemma-270m-it --data data/train.jsonl \
              --output-dir tuned --method lora --epochs 1 \
              --learning-rate 1e-5 --dtype float32 \
              --prompt-mode runtime_rendered --declarations tools.json

# 3. Convert, sweeping recipes rather than trusting a default.
litetune convert --model tuned/model --output-dir artifacts \
                 --recipe dynamic_wi8_afp32 --recipe weight_only_wi8_afp32

# 4. Measure what the conversion cost, against the float twin.
#    `convert` names the artifact; look the filename up rather than build it.
#    The prompt mode comes from the record `tune` left beside the checkpoint.
litetune verify --model artifacts/weight_only_wi8_afp32/<name>.litertlm \
                --reference tuned/model --data data/heldout.jsonl \
                --declarations tools.json --json > manifest.json

# 5. Package the artifact with what was measured about it.
litetune bundle --output-dir bundle \
                --model artifacts/weight_only_wi8_afp32/<name>.litertlm \
                --declarations tools.json --prompt-mode runtime_rendered \
                --base-model google/functiongemma-270m-it \
                --base-model-revision <commit-sha> \
                --adapter tuned/adapter \
                --train-metrics tuned/metrics.json \
                --verify-manifest manifest.json
```

`--prompt-mode runtime_rendered`, and `tools.json` passed to every stage, because
that is how this app calls the model: the declarations go to LiteRT-LM, which
renders them and parses the call back out. Train the other mode — `prerendered`,
where the application writes the declarations into the prompt text — and the
model is served a prompt it never saw. The value must be the **same** everywhere;
the wrong one produces a fluent wrong answer rather than an error.

`tools.json` is these four declarations in the shape `complete/lib/tools.dart`
sends them. `prepare` refuses shapes the runtime and the model's own chat
template render differently, which is why no declaration here carries an empty
`properties` map, and why every `multiply` row sends numbers rather than the
strings they used to be.

`--recipe` has no default, and litetune's own line for why is worth keeping:
*"A sweep of one is not a comparison."*

## Then open it in the app

Command 3 above — not the codelab's Step 3 — already gives you a `.litertlm`
per recipe under `artifacts/<recipe>/`.
Run `complete/`, choose **Open a .litertlm from disk**, and paste the absolute
path. Nothing in `lib/` changes — it is a `.litertlm`, and the app opens it the
way it opens the two it downloads.

On macOS the app is sandboxed, so a path under `~/Downloads` or in a scratch
directory is not readable from inside it. Copy the file into the app's own
documents directory — `~/Library/Containers/dev.fluttergemma.functioncalling/Data/Documents/`
— and paste that path.

## What this run actually measured

Run end to end on a MacBook Pro M4 Pro: `prepare` a second, `tune` 82s,
`convert` 84s for `weight_only_wi8_afp32`, `verify` 52s. The held-out split is
18 rows, scored through the runtime's tool path — a call counts only when the
operation name and every argument match.

| | picks the right tool |
|---|---|
| the published FunctionGemma this codelab downloads | 13 / 18 |
| tuned here, one epoch at 1e-5 | 18 / 18 |

The gain is in one place. The base model answers *"which system am I using?"*
with a refusal in prose — it never calls `get_device_info` — and four of its
five misses are that. After training it calls. Colours it already got right:
all six, before any training, which is worth knowing before you fine-tune
anything. Measure the base first and you may be done.

## The dial you are turning

Train the same 72 rows harder and the held-out score does not move — it is 18/18
at 1e-5, at 5e-5 and at three epochs of the default 2e-4 — while the model comes
apart behind it:

| | tool choice | after a tool result | plain question, no tools |
|---|---|---|---|
| base | 13 / 18 | narrates every tool | refuses, sometimes with a stray `<start_function_call>` |
| 1 epoch @ 1e-5 | 18 / 18 | narrates `multiply`, silent after a colour | same as base |
| 1 epoch @ 5e-5 | 18 / 18 | silent | a `<start_function_call>` before the prose |
| 3 epochs @ 2e-4 | 18 / 18 | silent | `<start_function_call>: Hello!` |

Every row here is a prompt and the call it should make, and nothing else. Train
on them hard enough and the model learns that a turn *is* a call — including
where this app needs prose: the sentence after a tool result. Held-out accuracy
cannot see it, because every held-out row is a tool call too.

There is no data fix inside litetune: it trains one user turn, and a row whose
prompt carries the call and the tool's response is refused in
`runtime_rendered` mode — those prompts are already rendered. The turn after a
result is not something you can teach here; it is something you avoid
destroying. Even at 1e-5 this run lost it for `change_background_color`, the
tool whose rows are newest and most uniform, while keeping it for `multiply`.

That is the honest shape of a fine-tune this small: it moves what you trained
and it costs what you did not. The app stays usable either way — the screen
still repaints, because the app acts on the tool's result rather than on the
model's sentence — and `complete/` downloads the stock models by default.

## Check the model you got, not the number

`verify` scores tool calls. Before you ship the artifact, ask it one thing that
is not one:

> hello, who are you?

with no tools in the session, and *"make the background blue"* with them. The
first must read like the base model's answer; the second must repaint AND say
so. A model that opens the first with `<start_function_call>`, or goes silent
on the second, is over-trained, whatever its held-out score says. Halve the
learning rate and convert again.

18 held-out rows is also too few to resolve anything: litetune says so on every
run, and the interval it prints spans more than the difference it measures.
Treat the pipeline as rehearsed and the numbers as a direction, then bring your
own data.
