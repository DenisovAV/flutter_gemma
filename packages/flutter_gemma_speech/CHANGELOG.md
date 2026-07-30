## 0.4.0
- Add VoiceSession — on-device push-to-talk voice loop (STT → LLM → TTS) with barge-in.

## 0.3.0
- feat: robust TTS text frontend — punctuation-as-symbols, numbers/acronyms, neural OOV G2P, clause chunking; fail-loud on overflow.

## 0.2.0
- Add on-device TTS (Matcha): installTts/getActiveTts, selectable model, PCM output.

## 0.1.0
- feat: on-device STT (moonshine-tiny) via `LiteRtSttBackend` + a generic, selectable `SttModelProfile` pipeline (encode → greedy decode → HF detokenize) on the shared LiteRT engine.
