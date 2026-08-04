## 0.4.1
- Add Qwen3-TTS (multilingual AR codec-LM, 11 languages) — 2nd selectable TTS family.

## 0.4.0
- feat: on-device Whisper-tiny STT (English-only) — log-mel frontend + GPT-2 BPE decode.
- feat: on-device Parakeet-CTC STT (desktop) — NeMo mel frontend + greedy CTC decode.

## 0.3.0
- Add VoiceSession — on-device push-to-talk voice loop (STT → LLM → TTS) with barge-in.
- feat: robust TTS text frontend — punctuation-as-symbols, numbers/acronyms, neural OOV G2P, clause chunking.
- fix: model-agnostic TTS chunking — word-boundary + duration-aware split so long replies fit MAX_TEXT/MAX_MEL.

## 0.2.0
- Add on-device TTS (Matcha): installTts/getActiveTts, selectable model, PCM output.

## 0.1.0
- feat: on-device STT (moonshine-tiny) via `LiteRtSttBackend` + a generic, selectable `SttModelProfile` pipeline (encode → greedy decode → HF detokenize) on the shared LiteRT engine.
