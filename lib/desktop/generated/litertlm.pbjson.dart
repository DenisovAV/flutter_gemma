// This is a generated file - do not edit.
//
// Generated from litertlm.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use initializeRequestDescriptor instead')
const InitializeRequest$json = {
  '1': 'InitializeRequest',
  '2': [
    {'1': 'model_path', '3': 1, '4': 1, '5': 9, '10': 'modelPath'},
    {'1': 'backend', '3': 2, '4': 1, '5': 9, '10': 'backend'},
    {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'enable_vision', '3': 4, '4': 1, '5': 8, '10': 'enableVision'},
    {'1': 'max_num_images', '3': 5, '4': 1, '5': 5, '10': 'maxNumImages'},
    {'1': 'enable_audio', '3': 6, '4': 1, '5': 8, '10': 'enableAudio'},
  ],
};

/// Descriptor for `InitializeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List initializeRequestDescriptor = $convert.base64Decode(
    'ChFJbml0aWFsaXplUmVxdWVzdBIdCgptb2RlbF9wYXRoGAEgASgJUgltb2RlbFBhdGgSGAoHYm'
    'Fja2VuZBgCIAEoCVIHYmFja2VuZBIdCgptYXhfdG9rZW5zGAMgASgFUgltYXhUb2tlbnMSIwoN'
    'ZW5hYmxlX3Zpc2lvbhgEIAEoCFIMZW5hYmxlVmlzaW9uEiQKDm1heF9udW1faW1hZ2VzGAUgAS'
    'gFUgxtYXhOdW1JbWFnZXMSIQoMZW5hYmxlX2F1ZGlvGAYgASgIUgtlbmFibGVBdWRpbw==');

@$core.Deprecated('Use initializeResponseDescriptor instead')
const InitializeResponse$json = {
  '1': 'InitializeResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'error', '3': 2, '4': 1, '5': 9, '10': 'error'},
    {'1': 'model_info', '3': 3, '4': 1, '5': 9, '10': 'modelInfo'},
  ],
};

/// Descriptor for `InitializeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List initializeResponseDescriptor = $convert.base64Decode(
    'ChJJbml0aWFsaXplUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxIUCgVlcnJvch'
    'gCIAEoCVIFZXJyb3ISHQoKbW9kZWxfaW5mbxgDIAEoCVIJbW9kZWxJbmZv');

@$core.Deprecated('Use createConversationRequestDescriptor instead')
const CreateConversationRequest$json = {
  '1': 'CreateConversationRequest',
  '2': [
    {'1': 'system_message', '3': 1, '4': 1, '5': 9, '10': 'systemMessage'},
    {
      '1': 'sampler_config',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.litertlm.SamplerConfig',
      '10': 'samplerConfig'
    },
  ],
};

/// Descriptor for `CreateConversationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createConversationRequestDescriptor = $convert.base64Decode(
    'ChlDcmVhdGVDb252ZXJzYXRpb25SZXF1ZXN0EiUKDnN5c3RlbV9tZXNzYWdlGAEgASgJUg1zeX'
    'N0ZW1NZXNzYWdlEj4KDnNhbXBsZXJfY29uZmlnGAIgASgLMhcubGl0ZXJ0bG0uU2FtcGxlckNv'
    'bmZpZ1INc2FtcGxlckNvbmZpZw==');

@$core.Deprecated('Use samplerConfigDescriptor instead')
const SamplerConfig$json = {
  '1': 'SamplerConfig',
  '2': [
    {'1': 'top_k', '3': 1, '4': 1, '5': 5, '10': 'topK'},
    {'1': 'top_p', '3': 2, '4': 1, '5': 2, '10': 'topP'},
    {'1': 'temperature', '3': 3, '4': 1, '5': 2, '10': 'temperature'},
  ],
};

/// Descriptor for `SamplerConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List samplerConfigDescriptor = $convert.base64Decode(
    'Cg1TYW1wbGVyQ29uZmlnEhMKBXRvcF9rGAEgASgFUgR0b3BLEhMKBXRvcF9wGAIgASgCUgR0b3'
    'BQEiAKC3RlbXBlcmF0dXJlGAMgASgCUgt0ZW1wZXJhdHVyZQ==');

@$core.Deprecated('Use createConversationResponseDescriptor instead')
const CreateConversationResponse$json = {
  '1': 'CreateConversationResponse',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'error', '3': 2, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `CreateConversationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createConversationResponseDescriptor =
    $convert.base64Decode(
        'ChpDcmVhdGVDb252ZXJzYXRpb25SZXNwb25zZRInCg9jb252ZXJzYXRpb25faWQYASABKAlSDm'
        'NvbnZlcnNhdGlvbklkEhQKBWVycm9yGAIgASgJUgVlcnJvcg==');

@$core.Deprecated('Use chatRequestDescriptor instead')
const ChatRequest$json = {
  '1': 'ChatRequest',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `ChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatRequestDescriptor = $convert.base64Decode(
    'CgtDaGF0UmVxdWVzdBInCg9jb252ZXJzYXRpb25faWQYASABKAlSDmNvbnZlcnNhdGlvbklkEh'
    'IKBHRleHQYAiABKAlSBHRleHQ=');

@$core.Deprecated('Use chatWithImageRequestDescriptor instead')
const ChatWithImageRequest$json = {
  '1': 'ChatWithImageRequest',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'image', '3': 3, '4': 1, '5': 12, '10': 'image'},
  ],
};

/// Descriptor for `ChatWithImageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatWithImageRequestDescriptor = $convert.base64Decode(
    'ChRDaGF0V2l0aEltYWdlUmVxdWVzdBInCg9jb252ZXJzYXRpb25faWQYASABKAlSDmNvbnZlcn'
    'NhdGlvbklkEhIKBHRleHQYAiABKAlSBHRleHQSFAoFaW1hZ2UYAyABKAxSBWltYWdl');

@$core.Deprecated('Use chatWithAudioRequestDescriptor instead')
const ChatWithAudioRequest$json = {
  '1': 'ChatWithAudioRequest',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'audio', '3': 3, '4': 1, '5': 12, '10': 'audio'},
  ],
};

/// Descriptor for `ChatWithAudioRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatWithAudioRequestDescriptor = $convert.base64Decode(
    'ChRDaGF0V2l0aEF1ZGlvUmVxdWVzdBInCg9jb252ZXJzYXRpb25faWQYASABKAlSDmNvbnZlcn'
    'NhdGlvbklkEhIKBHRleHQYAiABKAlSBHRleHQSFAoFYXVkaW8YAyABKAxSBWF1ZGlv');

@$core.Deprecated('Use chatResponseDescriptor instead')
const ChatResponse$json = {
  '1': 'ChatResponse',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'done', '3': 2, '4': 1, '5': 8, '10': 'done'},
    {'1': 'error', '3': 3, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `ChatResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatResponseDescriptor = $convert.base64Decode(
    'CgxDaGF0UmVzcG9uc2USEgoEdGV4dBgBIAEoCVIEdGV4dBISCgRkb25lGAIgASgIUgRkb25lEh'
    'QKBWVycm9yGAMgASgJUgVlcnJvcg==');

@$core.Deprecated('Use closeConversationRequestDescriptor instead')
const CloseConversationRequest$json = {
  '1': 'CloseConversationRequest',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
  ],
};

/// Descriptor for `CloseConversationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closeConversationRequestDescriptor =
    $convert.base64Decode(
        'ChhDbG9zZUNvbnZlcnNhdGlvblJlcXVlc3QSJwoPY29udmVyc2F0aW9uX2lkGAEgASgJUg5jb2'
        '52ZXJzYXRpb25JZA==');

@$core.Deprecated('Use closeConversationResponseDescriptor instead')
const CloseConversationResponse$json = {
  '1': 'CloseConversationResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `CloseConversationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closeConversationResponseDescriptor =
    $convert.base64Decode(
        'ChlDbG9zZUNvbnZlcnNhdGlvblJlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use shutdownRequestDescriptor instead')
const ShutdownRequest$json = {
  '1': 'ShutdownRequest',
};

/// Descriptor for `ShutdownRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List shutdownRequestDescriptor =
    $convert.base64Decode('Cg9TaHV0ZG93blJlcXVlc3Q=');

@$core.Deprecated('Use shutdownResponseDescriptor instead')
const ShutdownResponse$json = {
  '1': 'ShutdownResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `ShutdownResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List shutdownResponseDescriptor = $convert.base64Decode(
    'ChBTaHV0ZG93blJlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use healthCheckRequestDescriptor instead')
const HealthCheckRequest$json = {
  '1': 'HealthCheckRequest',
};

/// Descriptor for `HealthCheckRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List healthCheckRequestDescriptor =
    $convert.base64Decode('ChJIZWFsdGhDaGVja1JlcXVlc3Q=');

@$core.Deprecated('Use healthCheckResponseDescriptor instead')
const HealthCheckResponse$json = {
  '1': 'HealthCheckResponse',
  '2': [
    {'1': 'healthy', '3': 1, '4': 1, '5': 8, '10': 'healthy'},
    {'1': 'status', '3': 2, '4': 1, '5': 9, '10': 'status'},
  ],
};

/// Descriptor for `HealthCheckResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List healthCheckResponseDescriptor = $convert.base64Decode(
    'ChNIZWFsdGhDaGVja1Jlc3BvbnNlEhgKB2hlYWx0aHkYASABKAhSB2hlYWx0aHkSFgoGc3RhdH'
    'VzGAIgASgJUgZzdGF0dXM=');
