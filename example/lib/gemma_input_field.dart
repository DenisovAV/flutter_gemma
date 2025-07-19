import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_message.dart';
import 'package:flutter_gemma_example/services/gemma_service.dart';

class GemmaInputField extends StatefulWidget {
  const GemmaInputField({
    super.key,
    required this.messages,
    required this.streamHandler,
    required this.errorHandler,
    this.chat,
  });

  final InferenceChat? chat;
  final List<Message> messages;
  final ValueChanged<dynamic> streamHandler;
  final ValueChanged<String> errorHandler;

  @override
  GemmaInputFieldState createState() => GemmaInputFieldState();
}

class GemmaInputFieldState extends State<GemmaInputField> {
  GemmaLocalService? _gemma;
  var _message = const Message(text: '');
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _gemma = GemmaLocalService(widget.chat!);
    _processMessages();
  }

  void _processMessages() async {
    if (_processing) return;
    setState(() {
      _processing = true;
    });

    try {
      debugPrint('GemmaInputField: Processing message: "${widget.messages.last.text}"');
      final responseStream = await _gemma?.processMessage(widget.messages.last);
      
      if (responseStream != null) {
        await for (final response in responseStream) {
          if (!mounted) return;
          debugPrint('GemmaInputField: Received async response: $response');
          widget.streamHandler(response);
        }
      }
    } catch (e) {
      if (!mounted) return;
      widget.errorHandler(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ChatMessageWidget(message: _message),
    );
  }
}
