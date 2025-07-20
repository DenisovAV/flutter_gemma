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
  final ValueChanged<ModelResponse> streamHandler; // Отдает ModelResponse (токены или функции)
  final ValueChanged<String> errorHandler;

  @override
  GemmaInputFieldState createState() => GemmaInputFieldState();
}

class GemmaInputFieldState extends State<GemmaInputField> {
  GemmaLocalService? _gemma;
  var _message = const Message(text: '', isUser: false);
  bool _processing = false;
  StreamSubscription<ModelResponse>? _streamSubscription;
  FunctionCallResponse? _pendingFunctionCall; // Храним функцию для отправки в onDone

  @override
  void initState() {
    super.initState();
    _gemma = GemmaLocalService(widget.chat!);
    _processMessages();
  }

  @override
  void dispose() {
    debugPrint('GemmaInputField: dispose() called');
    _streamSubscription?.cancel();
    debugPrint('GemmaInputField: StreamSubscription cancelled');
    super.dispose();
  }

  void _processMessages() async {
    debugPrint('GemmaInputField: _processMessages() called');
    if (_processing) {
      debugPrint('GemmaInputField: Already processing, returning');
      return;
    }
    setState(() {
      _processing = true;
    });

    try {
      debugPrint('GemmaInputField: Processing message: "${widget.messages.last.text}"');
      final responseStream = await _gemma?.processMessage(widget.messages.last);
      debugPrint('GemmaInputField: Got response stream from GemmaLocalService');
      
      if (responseStream != null) {
        debugPrint('GemmaInputField: Creating StreamSubscription');
        _streamSubscription = responseStream.listen(
          (response) {
            debugPrint('GemmaInputField: Received token: $response');
            if (mounted) {
              // Accumulate tokens locally - don't call streamHandler yet!
              setState(() {
                if (response is String) {
                  // Обратная совместимость: строки из старого стрима
                  _message = Message(text: '${_message.text}$response', isUser: false);
                  debugPrint('GemmaInputField: Updated local message from String: "${_message.text}"');
                } else if (response is TextResponse) {
                  // Основной способ: получаем TextToken
                  _message = Message(text: '${_message.text}${response.token}', isUser: false);
                  debugPrint('GemmaInputField: Updated local message from TextToken: "${_message.text}"');
                } else if (response is FunctionCallResponse) {
                  // Сохраняем функцию для отправки в onDone
                  debugPrint('GemmaInputField: Function call received: ${response.name}');
                  _pendingFunctionCall = response;
                  // Не обновляем _message, тк функция - не текст
                }
              });
            } else {
              debugPrint('GemmaInputField: Widget not mounted, ignoring token');
            }
          },
          onError: (error) {
            debugPrint('GemmaInputField: Stream error: $error');
            if (mounted) {
              if (_pendingFunctionCall != null) {
                // Отправляем функцию при ошибке
                widget.streamHandler(_pendingFunctionCall!);
              } else {
                // Отправляем накопленный текст
                final text = _message.text.isNotEmpty ? _message.text : '...';
                widget.streamHandler(TextResponse(text));
              }
              widget.errorHandler(error.toString());
              setState(() {
                _processing = false;
              });
            }
          },
          onDone: () {
            debugPrint('GemmaInputField: Stream completed, sending final response');
            if (mounted) {
              if (_pendingFunctionCall != null) {
                // Отправляем функцию
                debugPrint('GemmaInputField: Sending function call: ${_pendingFunctionCall!.name}');
                widget.streamHandler(_pendingFunctionCall!);
              } else {
                // Отправляем накопленный текст как TextToken
                final text = _message.text.isNotEmpty ? _message.text : '...';
                debugPrint('GemmaInputField: Sending accumulated text as TextToken: "$text"');
                widget.streamHandler(TextResponse(text));
              }
              setState(() {
                _processing = false;
              });
              debugPrint('GemmaInputField: Processing set to false');
            }
          },
        );
        debugPrint('GemmaInputField: StreamSubscription created and listening');
      } else {
        debugPrint('GemmaInputField: responseStream is null!');
        if (mounted) {
          setState(() {
            _processing = false;
          });
        }
      }
    } catch (e) {
      debugPrint('GemmaInputField: Exception caught: $e');
      if (mounted) {
        widget.errorHandler(e.toString());
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
