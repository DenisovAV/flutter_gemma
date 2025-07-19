import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/chat_event.dart';
import 'package:flutter_gemma/core/function_call.dart';

class ChatResponseHandler {
  final InferenceChat _chat;
  
  ChatResponseHandler(this._chat);
  
  /// Process chat response with unified handling for both sync and async modes
  Stream<ChatEvent> processResponse({bool async = true, bool handleFunctions = false}) async* {
    try {
      if (async) {
        yield* _processAsyncResponse(handleFunctions: handleFunctions);
      } else {
        yield* _processSyncResponse(handleFunctions: handleFunctions);
      }
    } catch (e) {
      debugPrint('ChatResponseHandler error: $e');
      yield ErrorEvent(e.toString());
    }
  }
  
  /// Handle async streaming response
  Stream<ChatEvent> _processAsyncResponse({bool handleFunctions = false}) async* {
    debugPrint('ChatResponseHandler: Processing async response (handleFunctions: $handleFunctions)');
    
    if (!handleFunctions) {
      // Simple passthrough mode - no buffering
      await for (final token in _chat.generateChatResponseAsync()) {
        if (token is String) {
          yield TextTokenEvent(token);
        } else if (token is FunctionCall) {
          yield FunctionCallEvent(token);
        }
      }
      return;
    }
    
    // Function handling mode with smart buffering
    String buffer = '';
    bool isProcessingComplete = false;
    int tokenCount = 0;
    
    await for (final token in _chat.generateChatResponseAsync()) {
      if (token is String) {
        buffer += token;
        tokenCount++;
        
        if (!isProcessingComplete) {
          // Try to detect function call in buffer
          final functionCall = _tryParseFunctionCall(buffer);
          if (functionCall != null) {
            debugPrint('ChatResponseHandler: Detected function call in async stream');
            yield FunctionCallEvent(functionCall);
            isProcessingComplete = true;
            break;
          }
          
          // Check if we're confident this is regular text
          if (_isConfidentlyRegularText(buffer, tokenCount)) {
            debugPrint('ChatResponseHandler: Confident this is regular text, emitting buffered content');
            // Emit all buffered content as individual tokens
            for (int i = 0; i < buffer.length; i++) {
              yield TextTokenEvent(buffer[i]);
            }
            isProcessingComplete = true;
            // Continue processing remaining tokens
          }
        } else {
          // We're in regular text mode, emit tokens directly
          yield TextTokenEvent(token);
        }
      } else if (token is FunctionCall) {
        debugPrint('ChatResponseHandler: Received direct function call from stream');
        yield FunctionCallEvent(token);
        break;
      }
    }
  }
  
  /// Handle sync response
  Stream<ChatEvent> _processSyncResponse({bool handleFunctions = false}) async* {
    debugPrint('ChatResponseHandler: Processing sync response (handleFunctions: $handleFunctions)');
    
    final response = await _chat.generateChatResponse();
    
    if (response is String) {
      if (handleFunctions) {
        // Try to parse as function call first
        final functionCall = _tryParseFunctionCall(response);
        if (functionCall != null) {
          debugPrint('ChatResponseHandler: Detected function call in sync response');
          yield FunctionCallEvent(functionCall);
        } else {
          debugPrint('ChatResponseHandler: Emitting complete text response');
          yield TextCompleteEvent(response);
        }
      } else {
        // Simple mode - just emit text
        yield TextCompleteEvent(response);
      }
    } else if (response is FunctionCall) {
      debugPrint('ChatResponseHandler: Received direct function call from sync response');
      yield FunctionCallEvent(response);
    } else {
      debugPrint('ChatResponseHandler: Unknown response type: ${response.runtimeType}');
      yield ErrorEvent('Unknown response type: ${response.runtimeType}');
    }
  }
  
  /// Try to parse a function call from text
  FunctionCall? _tryParseFunctionCall(String text) {
    try {
      // Look for function call patterns
      if (text.contains('<tool_code>') && text.contains('</tool_code>')) {
        // Extract JSON from tool_code block
        final startTag = '<tool_code>';
        final endTag = '</tool_code>';
        final startIndex = text.indexOf(startTag);
        final endIndex = text.indexOf(endTag);
        
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          final jsonStr = text.substring(startIndex + startTag.length, endIndex).trim();
          final parsed = jsonDecode(jsonStr);
          
          if (parsed is Map<String, dynamic> && 
              parsed.containsKey('name') && 
              parsed.containsKey('parameters')) {
            return FunctionCall(
              name: parsed['name'] as String,
              args: Map<String, dynamic>.from(parsed['parameters'] as Map),
            );
          }
        }
      }
      
      // Try direct JSON parsing (in case the response is just JSON)
      if (text.startsWith('{') && text.contains('"name"')) {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic> && 
            parsed.containsKey('name')) {
          return FunctionCall(
            name: parsed['name'] as String,
            args: parsed.containsKey('parameters') 
                ? Map<String, dynamic>.from(parsed['parameters'] as Map)
                : parsed.containsKey('args')
                    ? Map<String, dynamic>.from(parsed['args'] as Map)
                    : <String, dynamic>{},
          );
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error parsing function call: $e');
      return null;
    }
  }
  
  /// Check if the buffer confidently looks like regular text (not a function call)
  bool _isConfidentlyRegularText(String buffer, int tokenCount) {
    // Wait for more tokens before deciding
    if (tokenCount < 20) {
      return false;
    }
    
    // Clean buffer for analysis
    final cleanBuffer = buffer.trim();
    
    // If we have substantial content and it doesn't look like JSON
    if (cleanBuffer.length > 30) {
      // Strong indicators it's NOT a function call:
      // 1. Doesn't start with { after cleaning
      // 2. Doesn't contain "name" in first 50 characters 
      // 3. Contains sentence patterns (spaces between words, punctuation)
      final first50 = cleanBuffer.length > 50 ? cleanBuffer.substring(0, 50) : cleanBuffer;
      
      final startsWithJson = cleanBuffer.startsWith('{') || cleanBuffer.startsWith('```json');
      final containsNameField = first50.contains('"name"');
      final containsToolCode = buffer.contains('<tool_code>');
      final looksLikeSentence = RegExp(r'[a-zA-Z]+\s+[a-zA-Z]+').hasMatch(first50);
      
      return !startsWithJson && !containsNameField && !containsToolCode && looksLikeSentence;
    }
    
    return false;
  }
}
