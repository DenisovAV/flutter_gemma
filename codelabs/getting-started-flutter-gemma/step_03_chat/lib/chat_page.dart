import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'model.dart';

/// A chat that waits for the whole reply before showing it.
///
/// Step 4 turns this into a stream; keeping the first version blocking makes
/// the difference easy to feel.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.model});

  final ModelChoice model;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _turns = <_Turn>[];

  InferenceModel? _inference;
  InferenceChat? _chat;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // maxTokens is the CONTEXT WINDOW — prompt + history + reply share it.
    // It is NOT a reply-length cap; for that, pass maxOutputTokens below.
    final inference = await FlutterGemma.getActiveModel(maxTokens: 1024);
    final chat = await inference.createChat(
      modelType: widget.model.modelType,
      maxOutputTokens: 256,
    );
    if (!mounted) return;
    setState(() {
      _inference = inference;
      _chat = chat;
    });
  }

  Future<void> _send() async {
    final chat = _chat;
    final text = _input.text.trim();
    if (chat == null || text.isEmpty || _busy) return;

    setState(() {
      _turns.add(_Turn(text, fromUser: true));
      _input.clear();
      _busy = true;
    });

    await chat.addQueryChunk(Message.text(text: text, isUser: true));
    final response = await chat.generateChatResponse();

    if (!mounted) return;
    setState(() {
      // ModelResponse is a sealed type: plain text, a tool call, or the
      // model's thinking. A first chat only ever needs the text arm.
      _turns.add(
        _Turn(switch (response) {
          TextResponse(:final token) => token,
          ThinkingResponse() => '(thinking)',
          _ => '(unsupported response)',
        }, fromUser: false),
      );
      _busy = false;
    });
  }

  @override
  void dispose() {
    // Sessions and models hold native memory — always close them.
    _inference?.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _chat != null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.model.label)),
      body: Column(
        children: [
          if (!ready) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _turns.length,
              itemBuilder: (context, i) => _Bubble(turn: _turns[i]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: ready && !_busy,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: ready
                            ? 'Ask something'
                            : 'Loading the model…',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: ready && !_busy ? _send : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Turn {
  const _Turn(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: turn.fromUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(turn.text),
      ),
    );
  }
}
