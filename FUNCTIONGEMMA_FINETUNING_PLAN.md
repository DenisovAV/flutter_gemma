# FunctionGemma Fine-tuning Guide

Complete guide for fine-tuning FunctionGemma 270M for custom function calling in flutter_gemma.

## Overview

FunctionGemma is Google's 270M parameter model specialized for function calling. Fine-tuning improves accuracy from ~58% to ~85% for specific functions.

**Key insight:** Fine-tuning does NOT eliminate the need for function declarations at runtime. Declarations are architecturally required by FunctionGemma format.

## Pipeline

```
1. functiongemma_finetuning.ipynb  - Fine-tune model (PyTorch/SafeTensors)
2. functiongemma_to_tflite.ipynb   - Convert to TFLite (ai-edge-torch)
3. functiongemma_tflite_to_task.ipynb - Bundle as .task (MediaPipe)
```

---

## Step 1: Fine-tuning (functiongemma_finetuning.ipynb)

### Requirements
- A100 GPU (Colab Pro)
- HuggingFace account with Gemma license accepted
- HF_TOKEN with write access in Colab Secrets

### Training Data Format

**Input format (training_data.jsonl):**
```json
{"user_content": "make it red", "tool_name": "change_background_color", "tool_arguments": "{\"color\": \"red\"}"}
{"user_content": "rename app to Hello", "tool_name": "change_app_title", "tool_arguments": "{\"title\": \"Hello\"}"}
{"user_content": "show alert saying hi", "tool_name": "show_alert", "tool_arguments": "{\"title\": \"Alert\", \"message\": \"hi\"}"}
```

**Converted to FunctionGemma format:**
```json
{
  "messages": [
    {"role": "developer", "content": "You are a model that can do function calling with the following functions"},
    {"role": "user", "content": "make it red"},
    {"role": "assistant", "tool_calls": [{"type": "function", "function": {"name": "change_background_color", "arguments": {"color": "red"}}}]}
  ],
  "tools": [... JSON schemas ...]
}
```

### Tools Definition

Tools are defined as Python functions with type hints and docstrings:

```python
def change_background_color(color: str) -> str:
    """Changes the app background color to specified color.

    Args:
        color: The color name (red, green, blue, yellow, purple, orange)
    """
    return f"Changed to {color}"

def change_app_title(title: str) -> str:
    """Changes the application title text in the AppBar.

    Args:
        title: The new title text to display
    """
    return f"Title set to {title}"

def show_alert(title: str, message: str) -> str:
    """Shows an alert dialog with a custom message and title.

    Args:
        title: The title of the alert dialog
        message: The message content of the alert dialog
    """
    return f"Alert shown: {title}"

# Generate JSON schemas
from transformers.utils import get_json_schema
TOOLS = [
    get_json_schema(change_background_color),
    get_json_schema(change_app_title),
    get_json_schema(show_alert),
]
```

### Critical: Developer Role System Message

**Official Google format (MUST use exactly):**
```python
DEFAULT_SYSTEM_MSG = "You are a model that can do function calling with the following functions"
```

**Why "developer" not "system":**
- FunctionGemma uses `developer` role to activate function calling mode
- Using `system` role will NOT work
- This is per official Google documentation

### Training Configuration

**Hyperparameters (from Google FunctionGemma cookbook):**

| Parameter | Value | Explanation |
|-----------|-------|-------------|
| `num_train_epochs` | 3 | 3 passes through dataset |
| `learning_rate` | 1e-5 | Conservative to prevent forgetting |
| `lr_scheduler_type` | cosine | Smooth decay |
| `gradient_accumulation_steps` | 8 | Effective batch = 32 |
| `max_length` | 1024 | Max sequence length |
| `bf16` | True | 16-bit training |
| `per_device_train_batch_size` | 4 | Batch per GPU |
| `warmup_ratio` | 0.1 | 10% warmup |

```python
from trl import SFTConfig, SFTTrainer

training_args = SFTConfig(
    output_dir=OUTPUT_DIR,
    max_length=1024,
    packing=False,
    num_train_epochs=3,
    per_device_train_batch_size=4,
    gradient_accumulation_steps=8,
    learning_rate=1e-5,
    lr_scheduler_type="cosine",
    optim="adamw_torch_fused",
    warmup_ratio=0.1,
    bf16=True,
    eval_strategy="epoch",
    save_strategy="epoch",
)

trainer = SFTTrainer(
    model=model,
    args=training_args,
    train_dataset=dataset['train'],
    eval_dataset=dataset['test'],
    processing_class=tokenizer,
)
```

### Model Loading (CRITICAL)

**Must use exact same parameters as training:**
```python
model = AutoModelForCausalLM.from_pretrained(
    "google/functiongemma-270m-it",
    torch_dtype=torch.bfloat16,        # CRITICAL: bfloat16, NOT float16!
    device_map="auto",
    attn_implementation="eager"         # CRITICAL: eager, NOT sdpa!
)
```

**Why these matter:**
- `bfloat16` - Model was trained in bfloat16, using float16 causes precision loss
- `eager` - FlashAttention causes issues with this model architecture

### Testing Fine-tuned Model

```python
test_prompt = "make the background red"

messages = [
    {"role": "developer", "content": DEFAULT_SYSTEM_MSG},
    {"role": "user", "content": test_prompt}
]

input_text = tokenizer.apply_chat_template(
    messages,
    tools=TOOLS,                    # Pass function schemas
    tokenize=False,
    add_generation_prompt=True
)

inputs = tokenizer(input_text, return_tensors="pt").to(model.device)
outputs = model.generate(**inputs, max_new_tokens=100, do_sample=False)
response = tokenizer.decode(outputs[0][inputs['input_ids'].shape[1]:], skip_special_tokens=False)

# Expected output:
# <start_function_call>call:change_background_color{color:<escape>red<escape>}<end_function_call>
```

### Output Files

After training, saved to Google Drive:
- `model.safetensors` - Model weights (~540MB)
- `config.json` - Architecture config
- `tokenizer.json` - Tokenizer
- `tokenizer.model` - SentencePiece model
- `tokenizer_config.json` - Tokenizer config
- `special_tokens_map.json` - Special tokens

---

## Step 2: TFLite Conversion (functiongemma_to_tflite.ipynb)

### Requirements
- A100 or L4 GPU
- Fine-tuned model from Step 1 in Google Drive

### Installation

```bash
pip install ai-edge-torch --force-reinstall
pip install "numpy<2.1" --force-reinstall  # CRITICAL: After ai-edge-torch
pip install transformers==4.57.3
pip install Pillow --force-reinstall  # Restore after ai-edge-torch
```

**RESTART RUNTIME after installation!**

### Pre-conversion Validation

**Always test model BEFORE conversion:**
```python
# Load with SAME parameters as training
hf_model = AutoModelForCausalLM.from_pretrained(
    MODEL_DIR,
    torch_dtype=torch.bfloat16,
    device_map="auto",
    attn_implementation="eager"
)

# Test generation
# If output is garbage here, problem is in fine-tuning, NOT conversion
```

**Validation checks:**
- Output contains `<start_function_call>` - OK
- Output contains `<pad>` tokens - Wrong loading params
- Output is Chinese/garbage - Fine-tuning broken
- Output says "sorry/apologize" - Model refusing to call functions

### Conversion

```python
from ai_edge_torch.generative.examples.gemma3 import gemma3
from ai_edge_torch.generative.utilities import converter
from ai_edge_torch.generative.utilities.export_config import ExportConfig
from ai_edge_torch.generative.layers import kv_cache

# Load via ai-edge-torch
pytorch_model = gemma3.build_model_270m(MODEL_DIR)
pytorch_model.eval()

# Configure export
export_config = ExportConfig()
export_config.kvcache_layout = kv_cache.KV_LAYOUT_TRANSPOSED
export_config.mask_as_input = True

# Convert with Google official parameters
converter.convert_to_tflite(
    pytorch_model,
    output_path=TFLITE_OUTPUT_DIR,
    output_name_prefix="functiongemma-flutter",
    prefill_seq_len=256,       # Official Google parameter
    kv_cache_max_len=1024,     # Max context length
    quantize="dynamic_int8",   # Reduces size ~50%
    export_config=export_config,
)
```

**Conversion parameters:**

| Parameter | Value | Description |
|-----------|-------|-------------|
| `prefill_seq_len` | 256 | Input sequence length |
| `kv_cache_max_len` | 1024 | Maximum context (can increase to 2048) |
| `quantize` | dynamic_int8 | Reduces ~540MB to ~270MB |

### Output

- `functiongemma-flutter_q8_ekv1024.tflite` (~270MB)
- Tokenizer copied alongside

---

## Step 3: Task Bundle (functiongemma_tflite_to_task.ipynb)

### Requirements
- TFLite file from Step 2
- Tokenizer.model

### Installation

```bash
pip install mediapipe==0.10.20
pip install "numpy<2.1" --force-reinstall
# RESTART RUNTIME!
```

### Bundle Configuration

```python
from mediapipe.tasks.python.genai import bundler

config = bundler.BundleConfig(
    tflite_model=TFLITE_MODEL,
    tokenizer_model=TOKENIZER_PATH,
    start_token="<bos>",
    stop_tokens=[
        "<eos>",
        "<end_of_turn>",
        "<end_function_call>",
        "<start_function_response>",  # CRITICAL: Model stops after function call!
    ],
    output_filename="functiongemma-flutter.task",
    prompt_prefix="<start_of_turn>user\n",
    prompt_suffix="<end_of_turn>\n<start_of_turn>model\n",
)

bundler.create_bundle(config)
```

**Critical stop tokens:**
- `<end_function_call>` - End of function call
- `<start_function_response>` - Model must STOP here and wait for function result

### Output

- `.task` file (~284MB) - Ready for Flutter

---

## Troubleshooting

### Model outputs garbage after conversion
- Check loading params: `bfloat16` + `eager`
- Test model BEFORE conversion
- If pre-conversion test fails, re-run fine-tuning

### Model outputs `<pad>` tokens
- Wrong dtype: Use `bfloat16`, not `float16`
- Wrong attention: Use `eager`, not default

### numpy binary incompatibility error
- Install `numpy<2.1` AFTER ai-edge-torch/mediapipe
- RESTART RUNTIME after installation

### 403 Forbidden on HuggingFace upload
- Token needs Write access (not Fine-grained read-only)
- Create new token with Write permissions

---

## Training Data Examples (284 total)

### change_background_color (94 examples)
```
"make it red" → change_background_color(color="red")
"change to blue" → change_background_color(color="blue")
"set background green" → change_background_color(color="green")
"I want a purple background" → change_background_color(color="purple")
"make the background orange" → change_background_color(color="orange")
```

### change_app_title (95 examples)
```
"rename the app to Hello" → change_app_title(title="Hello")
"set title to My App" → change_app_title(title="My App")
"change the title to Test" → change_app_title(title="Test")
"call it Flutter Demo" → change_app_title(title="Flutter Demo")
```

### show_alert (95 examples)
```
"show an alert saying welcome" → show_alert(title="Alert", message="welcome")
"display a message hello world" → show_alert(title="Message", message="hello world")
"pop up an alert with error" → show_alert(title="Alert", message="error")
```

---

## License

Models converted from FunctionGemma must include:

```
Gemma is provided under and subject to the Gemma Terms of Use found at https://ai.google.dev/gemma/terms
```

Redistribution is allowed with proper attribution.
