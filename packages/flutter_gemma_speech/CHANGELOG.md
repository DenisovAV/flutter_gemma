## 0.2.0
- Add on-device TTS (Matcha): installTts/getActiveTts, selectable model, PCM output.

## 0.1.0
- feat: on-device STT (moonshine-tiny) via `LiteRtSttBackend` + a generic, selectable `SttModelProfile` pipeline (encode → greedy decode → HF detokenize) on the shared LiteRT engine.
