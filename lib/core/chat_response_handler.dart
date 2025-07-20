import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/chat_event.dart';
import 'package:flutter_gemma/core/function_call.dart';
import 'package:flutter_gemma/core/function_call_parser.dart';

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
        yield TextTokenEvent(token);
      }
      return;
    }
    
    // Smart function handling mode
    String buffer = '';
    bool isJsonMode = false;
    bool decisionMade = false;
    bool functionProcessed = false;
    
    await for (final token in _chat.generateChatResponseAsync()) {
      // Step 1: Determine JSON or text mode (only once!)
      if (!decisionMade) {
        buffer += token;
        
        if (FunctionCallParser.isJsonStart(buffer)) {
          isJsonMode = true;
          decisionMade = true;
          debugPrint('ChatResponseHandler: Detected JSON mode');
        } else if (FunctionCallParser.isDefinitelyText(buffer)) {
          isJsonMode = false;
          decisionMade = true;
          debugPrint('ChatResponseHandler: Detected text mode - streaming immediately');
          // Emit accumulated buffer as single token
          yield TextTokenEvent(buffer);
          buffer = ''; // Clear buffer to avoid duplication
        }
      } else {
        // Step 2: Process based on determined mode (don't buffer anymore!)
        if (isJsonMode && !functionProcessed) {
          // JSON mode - buffer until complete
          buffer += token;
          if (FunctionCallParser.isJsonComplete(buffer)) {
            final functionCall = FunctionCallParser.parse(buffer);
            if (functionCall != null) {
              debugPrint('ChatResponseHandler: Function call parsed successfully');
              yield FunctionCallEvent(functionCall);
              functionProcessed = true;
              buffer = ''; // Clear buffer, rest will be text response
            }
          }
        } else if (!isJsonMode) {
          // Text mode - stream tokens directly (no buffering needed)
          yield TextTokenEvent(token);
        }
      }
    }
    
    // Handle end of stream - process any remaining buffer
    if (buffer.isNotEmpty && !functionProcessed) {
      if (isJsonMode) {
        final functionCall = FunctionCallParser.parse(buffer);
        if (functionCall != null) {
          debugPrint('ChatResponseHandler: Function call found at end of stream');
          yield FunctionCallEvent(functionCall);
        } else {
          debugPrint('ChatResponseHandler: Incomplete JSON at end of stream, emitting as text');
          yield TextTokenEvent(buffer);
        }
      } else if (buffer.isNotEmpty) {
        debugPrint('ChatResponseHandler: Emitting remaining buffer as text');
        yield TextTokenEvent(buffer);
      }
    }
  }
  
  /// Handle sync response
  Stream<ChatEvent> _processSyncResponse({bool handleFunctions = false}) async* {
    debugPrint('ChatResponseHandler: Processing sync response (handleFunctions: $handleFunctions)');
    
    final response = await _chat.generateChatResponse();
    
    if (handleFunctions) {
      // Try to parse as function call using unified parser
      final functionCall = FunctionCallParser.parse(response);
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
  }
}
