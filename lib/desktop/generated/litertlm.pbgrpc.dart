// This is a generated file - do not edit.
//
// Generated from litertlm.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'litertlm.pb.dart' as $0;

export 'litertlm.pb.dart';

@$pb.GrpcServiceName('litertlm.LiteRtLmService')
class LiteRtLmServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  LiteRtLmServiceClient(super.channel, {super.options, super.interceptors});

  /// Initialize engine with model
  $grpc.ResponseFuture<$0.InitializeResponse> initialize(
    $0.InitializeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$initialize, request, options: options);
  }

  /// Create new conversation
  $grpc.ResponseFuture<$0.CreateConversationResponse> createConversation(
    $0.CreateConversationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createConversation, request, options: options);
  }

  /// Send message and stream response
  $grpc.ResponseStream<$0.ChatResponse> chat(
    $0.ChatRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$chat, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Send message with image (multimodal)
  $grpc.ResponseStream<$0.ChatResponse> chatWithImage(
    $0.ChatWithImageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$chatWithImage, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Send message with image SYNC (for testing)
  $grpc.ResponseFuture<$0.ChatResponse> chatWithImageSync(
    $0.ChatWithImageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$chatWithImageSync, request, options: options);
  }

  /// Send message with audio (Gemma 3n E4B)
  $grpc.ResponseStream<$0.ChatResponse> chatWithAudio(
    $0.ChatWithAudioRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$chatWithAudio, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// Close conversation
  $grpc.ResponseFuture<$0.CloseConversationResponse> closeConversation(
    $0.CloseConversationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$closeConversation, request, options: options);
  }

  /// Shutdown engine
  $grpc.ResponseFuture<$0.ShutdownResponse> shutdown(
    $0.ShutdownRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$shutdown, request, options: options);
  }

  /// Health check
  $grpc.ResponseFuture<$0.HealthCheckResponse> healthCheck(
    $0.HealthCheckRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$healthCheck, request, options: options);
  }

  // method descriptors

  static final _$initialize =
      $grpc.ClientMethod<$0.InitializeRequest, $0.InitializeResponse>(
          '/litertlm.LiteRtLmService/Initialize',
          ($0.InitializeRequest value) => value.writeToBuffer(),
          $0.InitializeResponse.fromBuffer);
  static final _$createConversation = $grpc.ClientMethod<
          $0.CreateConversationRequest, $0.CreateConversationResponse>(
      '/litertlm.LiteRtLmService/CreateConversation',
      ($0.CreateConversationRequest value) => value.writeToBuffer(),
      $0.CreateConversationResponse.fromBuffer);
  static final _$chat = $grpc.ClientMethod<$0.ChatRequest, $0.ChatResponse>(
      '/litertlm.LiteRtLmService/Chat',
      ($0.ChatRequest value) => value.writeToBuffer(),
      $0.ChatResponse.fromBuffer);
  static final _$chatWithImage =
      $grpc.ClientMethod<$0.ChatWithImageRequest, $0.ChatResponse>(
          '/litertlm.LiteRtLmService/ChatWithImage',
          ($0.ChatWithImageRequest value) => value.writeToBuffer(),
          $0.ChatResponse.fromBuffer);
  static final _$chatWithImageSync =
      $grpc.ClientMethod<$0.ChatWithImageRequest, $0.ChatResponse>(
          '/litertlm.LiteRtLmService/ChatWithImageSync',
          ($0.ChatWithImageRequest value) => value.writeToBuffer(),
          $0.ChatResponse.fromBuffer);
  static final _$chatWithAudio =
      $grpc.ClientMethod<$0.ChatWithAudioRequest, $0.ChatResponse>(
          '/litertlm.LiteRtLmService/ChatWithAudio',
          ($0.ChatWithAudioRequest value) => value.writeToBuffer(),
          $0.ChatResponse.fromBuffer);
  static final _$closeConversation = $grpc.ClientMethod<
          $0.CloseConversationRequest, $0.CloseConversationResponse>(
      '/litertlm.LiteRtLmService/CloseConversation',
      ($0.CloseConversationRequest value) => value.writeToBuffer(),
      $0.CloseConversationResponse.fromBuffer);
  static final _$shutdown =
      $grpc.ClientMethod<$0.ShutdownRequest, $0.ShutdownResponse>(
          '/litertlm.LiteRtLmService/Shutdown',
          ($0.ShutdownRequest value) => value.writeToBuffer(),
          $0.ShutdownResponse.fromBuffer);
  static final _$healthCheck =
      $grpc.ClientMethod<$0.HealthCheckRequest, $0.HealthCheckResponse>(
          '/litertlm.LiteRtLmService/HealthCheck',
          ($0.HealthCheckRequest value) => value.writeToBuffer(),
          $0.HealthCheckResponse.fromBuffer);
}

@$pb.GrpcServiceName('litertlm.LiteRtLmService')
abstract class LiteRtLmServiceBase extends $grpc.Service {
  $core.String get $name => 'litertlm.LiteRtLmService';

  LiteRtLmServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.InitializeRequest, $0.InitializeResponse>(
        'Initialize',
        initialize_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.InitializeRequest.fromBuffer(value),
        ($0.InitializeResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateConversationRequest,
            $0.CreateConversationResponse>(
        'CreateConversation',
        createConversation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateConversationRequest.fromBuffer(value),
        ($0.CreateConversationResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ChatRequest, $0.ChatResponse>(
        'Chat',
        chat_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.ChatRequest.fromBuffer(value),
        ($0.ChatResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ChatWithImageRequest, $0.ChatResponse>(
        'ChatWithImage',
        chatWithImage_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.ChatWithImageRequest.fromBuffer(value),
        ($0.ChatResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ChatWithImageRequest, $0.ChatResponse>(
        'ChatWithImageSync',
        chatWithImageSync_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ChatWithImageRequest.fromBuffer(value),
        ($0.ChatResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ChatWithAudioRequest, $0.ChatResponse>(
        'ChatWithAudio',
        chatWithAudio_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.ChatWithAudioRequest.fromBuffer(value),
        ($0.ChatResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CloseConversationRequest,
            $0.CloseConversationResponse>(
        'CloseConversation',
        closeConversation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CloseConversationRequest.fromBuffer(value),
        ($0.CloseConversationResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ShutdownRequest, $0.ShutdownResponse>(
        'Shutdown',
        shutdown_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ShutdownRequest.fromBuffer(value),
        ($0.ShutdownResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.HealthCheckRequest, $0.HealthCheckResponse>(
            'HealthCheck',
            healthCheck_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.HealthCheckRequest.fromBuffer(value),
            ($0.HealthCheckResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.InitializeResponse> initialize_Pre($grpc.ServiceCall $call,
      $async.Future<$0.InitializeRequest> $request) async {
    return initialize($call, await $request);
  }

  $async.Future<$0.InitializeResponse> initialize(
      $grpc.ServiceCall call, $0.InitializeRequest request);

  $async.Future<$0.CreateConversationResponse> createConversation_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateConversationRequest> $request) async {
    return createConversation($call, await $request);
  }

  $async.Future<$0.CreateConversationResponse> createConversation(
      $grpc.ServiceCall call, $0.CreateConversationRequest request);

  $async.Stream<$0.ChatResponse> chat_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ChatRequest> $request) async* {
    yield* chat($call, await $request);
  }

  $async.Stream<$0.ChatResponse> chat(
      $grpc.ServiceCall call, $0.ChatRequest request);

  $async.Stream<$0.ChatResponse> chatWithImage_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ChatWithImageRequest> $request) async* {
    yield* chatWithImage($call, await $request);
  }

  $async.Stream<$0.ChatResponse> chatWithImage(
      $grpc.ServiceCall call, $0.ChatWithImageRequest request);

  $async.Future<$0.ChatResponse> chatWithImageSync_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ChatWithImageRequest> $request) async {
    return chatWithImageSync($call, await $request);
  }

  $async.Future<$0.ChatResponse> chatWithImageSync(
      $grpc.ServiceCall call, $0.ChatWithImageRequest request);

  $async.Stream<$0.ChatResponse> chatWithAudio_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ChatWithAudioRequest> $request) async* {
    yield* chatWithAudio($call, await $request);
  }

  $async.Stream<$0.ChatResponse> chatWithAudio(
      $grpc.ServiceCall call, $0.ChatWithAudioRequest request);

  $async.Future<$0.CloseConversationResponse> closeConversation_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CloseConversationRequest> $request) async {
    return closeConversation($call, await $request);
  }

  $async.Future<$0.CloseConversationResponse> closeConversation(
      $grpc.ServiceCall call, $0.CloseConversationRequest request);

  $async.Future<$0.ShutdownResponse> shutdown_Pre($grpc.ServiceCall $call,
      $async.Future<$0.ShutdownRequest> $request) async {
    return shutdown($call, await $request);
  }

  $async.Future<$0.ShutdownResponse> shutdown(
      $grpc.ServiceCall call, $0.ShutdownRequest request);

  $async.Future<$0.HealthCheckResponse> healthCheck_Pre($grpc.ServiceCall $call,
      $async.Future<$0.HealthCheckRequest> $request) async {
    return healthCheck($call, await $request);
  }

  $async.Future<$0.HealthCheckResponse> healthCheck(
      $grpc.ServiceCall call, $0.HealthCheckRequest request);
}
