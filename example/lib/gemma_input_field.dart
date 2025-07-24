import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_message.dart';
import 'package:flutter_gemma_example/services/gemma_service.dart';
import 'package:flutter_gemma_example/thinking_widget.dart';

class GemmaInputField extends StatefulWidget {
  const GemmaInputField({
    super.key,
    required this.messages,
    required this.streamHandler,
    required this.errorHandler,
    this.chat,
    this.onThinkingCompleted,
  });

  final InferenceChat? chat;
  final List<Message> messages;
  final ValueChanged<ModelResponse> streamHandler; // Отдает ModelResponse (токены или функции)
  final ValueChanged<String> errorHandler;
  final ValueChanged<String>? onThinkingCompleted; // Callback для завершенного thinking content

  @override
  GemmaInputFieldState createState() => GemmaInputFieldState();
}

class GemmaInputFieldState extends State<GemmaInputField> {
  GemmaLocalService? _gemma;
  var _message = const Message(text: '', isUser: false);
  bool _processing = false;
  StreamSubscription<ModelResponse>? _streamSubscription;
  FunctionCallResponse? _pendingFunctionCall; // Храним функцию для отправки в onDone
  String _thinkingContent = ''; // Накапливаем thinking content
  bool _isThinkingExpanded = false; // Состояние раскрытия thinking блока
  bool _thinkingCompleted = false; // Thinking завершен
  ThinkingResponse? _completedThinking; // Сохраняем завершенный thinking

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
      _message = const Message(text: '', isUser: false); // Сбрасываем сообщение
      _thinkingContent = ''; // Сбрасываем thinking content
      _thinkingCompleted = false; // Сбрасываем флаг завершения
      _completedThinking = null; // Сбрасываем сохраненный thinking
      _pendingFunctionCall = null; // Сбрасываем pending function
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
                } else if (response is ThinkingResponse) {
                  // Накапливаем thinking content
                  _thinkingContent += response.content;
                  debugPrint('GemmaInputField: Accumulated thinking content: "$_thinkingContent"');
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
              // Сохраняем thinking как завершенный и передаем в родительский widget
              if (_thinkingContent.isNotEmpty) {
                debugPrint('GemmaInputField: Marking thinking as completed. Content length: ${_thinkingContent.length}');
                setState(() {
                  _thinkingCompleted = true;
                  _completedThinking = ThinkingResponse(_thinkingContent);
                });
                // Передаем thinking content в родительский widget для постоянного отображения
                widget.onThinkingCompleted?.call(_thinkingContent);
              } else {
                debugPrint('GemmaInputField: No thinking content to complete');
              }
              
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
                debugPrint('GemmaInputField: Final state - thinking completed: $_thinkingCompleted, content: "$_thinkingContent"');
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
    debugPrint('GemmaInputField: Building widget - thinking content: "$_thinkingContent", completed: $_thinkingCompleted, processing: $_processing');
    return SingleChildScrollView(
      child: Column(
        children: [
          // Показываем thinking блок если есть thinking content или сохраненный thinking
          if (_thinkingContent.isNotEmpty || _completedThinking != null) ...[
            if (_thinkingCompleted && _completedThinking != null)
              // Завершенный thinking блок
              ThinkingWidget(
                thinking: _completedThinking!,
                isExpanded: _isThinkingExpanded,
                onToggle: () {
                  setState(() {
                    _isThinkingExpanded = !_isThinkingExpanded;
                  });
                },
              )
            else
              // Thinking в процессе
              StreamingThinkingWidget(
                content: _thinkingContent,
                isExpanded: _isThinkingExpanded,
                onToggle: () {
                  setState(() {
                    _isThinkingExpanded = !_isThinkingExpanded;
                  });
                },
              ),
          ],
          // Основное сообщение
          ChatMessageWidget(message: _message),
        ],
      ),
    );
  }
}
