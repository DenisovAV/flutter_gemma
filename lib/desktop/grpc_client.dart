import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import 'generated/litertlm.pbgrpc.dart';
import 'server_process_manager.dart';

/// gRPC client wrapper for LiteRT-LM server communication
class LiteRtLmClient {
  ClientChannel? _channel;
  LiteRtLmServiceClient? _client;
  String? _currentConversationId;
  bool _isInitialized = false;

  /// Whether the client is connected and model is initialized
  bool get isInitialized => _isInitialized;

  /// Current conversation ID
  String? get conversationId => _currentConversationId;

  /// Connect to the gRPC server
  Future<void> connect({String host = 'localhost', int? port}) async {
    final serverPort = port ?? ServerProcessManager.instance.port;

    _channel = ClientChannel(
      host,
      port: serverPort,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );

    _client = LiteRtLmServiceClient(_channel!);

    debugPrint('[LiteRtLmClient] Connected to $host:$serverPort');
  }

  /// Initialize the model
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    int maxTokens = 2048,
  }) async {
    _assertConnected();

    final request = InitializeRequest()
      ..modelPath = modelPath
      ..backend = backend
      ..maxTokens = maxTokens;

    final response = await _client!.initialize(request);

    if (!response.success) {
      throw Exception('Failed to initialize model: ${response.error}');
    }

    _isInitialized = true;
    debugPrint('[LiteRtLmClient] Model initialized: ${response.modelInfo}');
  }

  /// Create a new conversation
  Future<String> createConversation({String? systemMessage}) async {
    _assertInitialized();

    final request = CreateConversationRequest();
    if (systemMessage != null) {
      request.systemMessage = systemMessage;
    }

    final response = await _client!.createConversation(request);

    if (response.hasError() && response.error.isNotEmpty) {
      throw Exception('Failed to create conversation: ${response.error}');
    }

    _currentConversationId = response.conversationId;
    debugPrint('[LiteRtLmClient] Conversation created: $_currentConversationId');

    return _currentConversationId!;
  }

  /// Timeout for streaming responses (5 minutes for long generation)
  static const _streamTimeout = Duration(minutes: 5);

  /// Send a chat message and get streaming response
  Stream<String> chat(String text, {String? conversationId}) async* {
    _assertInitialized();

    final convId = conversationId ?? _currentConversationId;
    if (convId == null) {
      throw StateError('No conversation. Call createConversation() first.');
    }

    final request = ChatRequest()
      ..conversationId = convId
      ..text = text;

    // Add timeout to prevent infinite hanging
    await for (final response in _client!.chat(request).timeout(
      _streamTimeout,
      onTimeout: (sink) {
        sink.addError(TimeoutException(
          'Model response timed out after ${_streamTimeout.inMinutes} minutes',
        ));
        sink.close();
      },
    )) {
      if (response.hasError() && response.error.isNotEmpty) {
        throw Exception('Chat error: ${response.error}');
      }

      if (response.hasText()) {
        yield response.text;
      }
    }
  }

  /// Send a multimodal chat message (text + image)
  Stream<String> chatWithImage(
    String text,
    Uint8List imageBytes, {
    String? conversationId,
  }) async* {
    _assertInitialized();

    final convId = conversationId ?? _currentConversationId;
    if (convId == null) {
      throw StateError('No conversation. Call createConversation() first.');
    }

    final request = ChatWithImageRequest()
      ..conversationId = convId
      ..text = text
      ..image = imageBytes;

    // Add timeout to prevent infinite hanging
    await for (final response in _client!.chatWithImage(request).timeout(
      _streamTimeout,
      onTimeout: (sink) {
        sink.addError(TimeoutException(
          'Model response timed out after ${_streamTimeout.inMinutes} minutes',
        ));
        sink.close();
      },
    )) {
      if (response.hasError() && response.error.isNotEmpty) {
        throw Exception('Chat error: ${response.error}');
      }

      if (response.hasText()) {
        yield response.text;
      }
    }
  }

  /// Close current conversation
  Future<void> closeConversation({String? conversationId}) async {
    final convId = conversationId ?? _currentConversationId;
    if (convId == null) return;

    try {
      final request = CloseConversationRequest()..conversationId = convId;
      await _client!.closeConversation(request);

      if (convId == _currentConversationId) {
        _currentConversationId = null;
      }

      debugPrint('[LiteRtLmClient] Conversation closed: $convId');
    } catch (e) {
      debugPrint('[LiteRtLmClient] Warning: Failed to close conversation: $e');
    }
  }

  /// Shutdown the model engine
  Future<void> shutdown() async {
    if (_client == null) return;

    try {
      await _client!.shutdown(ShutdownRequest());
      _isInitialized = false;
      debugPrint('[LiteRtLmClient] Engine shut down');
    } catch (e) {
      debugPrint('[LiteRtLmClient] Warning: Failed to shutdown: $e');
    }
  }

  /// Health check
  Future<bool> healthCheck() async {
    if (_client == null) return false;

    try {
      final response = await _client!.healthCheck(HealthCheckRequest());
      return response.healthy; // Use boolean field, not status string
    } catch (e) {
      return false;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    await _channel?.shutdown();
    _channel = null;
    _client = null;
    _isInitialized = false;
    _currentConversationId = null;

    debugPrint('[LiteRtLmClient] Disconnected');
  }

  void _assertConnected() {
    if (_client == null) {
      throw StateError('Not connected. Call connect() first.');
    }
  }

  void _assertInitialized() {
    _assertConnected();
    if (!_isInitialized) {
      throw StateError('Model not initialized. Call initialize() first.');
    }
  }
}
