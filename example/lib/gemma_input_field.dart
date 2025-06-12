import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_message.dart';
import 'package:flutter_gemma_example/services/gemma_service.dart';
import 'dart:io';

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
  final ValueChanged<Message> streamHandler;
  final ValueChanged<String> errorHandler;

  @override
  GemmaInputFieldState createState() => GemmaInputFieldState();
}

class GemmaInputFieldState extends State<GemmaInputField> {
  GemmaLocalService? _gemma;
  StreamSubscription<String?>? _subscription;
  var _message = const Message(text: '');
  bool _isGenerating = true;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _gemma = GemmaLocalService(widget.chat!);
    _processMessages();
  }

  void _processMessages() {
    _subscription = _gemma?.processMessageAsync(widget.messages.last).listen(
      (String token) {
        if (!mounted || !_isGenerating) return;
        setState(() {
          _message = Message(text: '${_message.text}$token');
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isGenerating = false;
        });
        if (_message.text.isEmpty) {
          _message = const Message(text: '...');
        }
        widget.streamHandler(_message);
        _subscription?.cancel();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isGenerating = false;
        });
        debugPrint('Error: $error');

        // Preserve partial response even on error
        if (_message.text.isEmpty) {
          _message = const Message(text: '...');
        }
        widget.streamHandler(_message);

        // Only show error if it's not a cancellation-related error
        final errorString = error.toString();
        if (!errorString.contains('Previous invocation still processing') &&
            !errorString.contains('cancelled')) {
          widget.errorHandler(errorString);
        }
        _subscription?.cancel();
      },
    );
  }

  Future<void> _stopGeneration() async {
    if (_gemma != null && _isGenerating && !_isCancelling) {
      setState(() {
        _isCancelling = true;
      });

      try {
        await _gemma!.cancelGenerateResponseAsync();

        // Ensure we have some content to show
        if (_message.text.isEmpty) {
          _message = const Message(text: '...');
        }

        // Preserve partial response
        widget.streamHandler(_message);

        // Clean up subscription
        await _subscription?.cancel();
      } catch (e) {
        debugPrint('Error stopping generation: $e');
        // Even on error, try to preserve what we have
        if (_message.text.isNotEmpty) {
          widget.streamHandler(_message);
        }
        widget.errorHandler('Failed to stop generation: $e');
      } finally {
        setState(() {
          _isGenerating = false;
          _isCancelling = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: ChatMessageWidget(message: _message),
          ),
        ),
        if (_isGenerating && Platform.isAndroid)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: _isCancelling ? null : _stopGeneration,
              icon: _isCancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.stop),
              label: Text(_isCancelling ? 'Stopping...' : 'Stop Generation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.blue.shade300,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                padding: const EdgeInsets.symmetric(vertical: 12.0),
              ),
            ),
          ),
      ],
    );
  }
}
