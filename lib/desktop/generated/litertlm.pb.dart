// This is a generated file - do not edit.
//
// Generated from litertlm.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class InitializeRequest extends $pb.GeneratedMessage {
  factory InitializeRequest({
    $core.String? modelPath,
    $core.String? backend,
    $core.int? maxTokens,
    $core.bool? enableVision,
    $core.int? maxNumImages,
  }) {
    final result = create();
    if (modelPath != null) result.modelPath = modelPath;
    if (backend != null) result.backend = backend;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (enableVision != null) result.enableVision = enableVision;
    if (maxNumImages != null) result.maxNumImages = maxNumImages;
    return result;
  }

  InitializeRequest._();

  factory InitializeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InitializeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InitializeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelPath')
    ..aOS(2, _omitFieldNames ? '' : 'backend')
    ..aI(3, _omitFieldNames ? '' : 'maxTokens')
    ..aOB(4, _omitFieldNames ? '' : 'enableVision')
    ..aI(5, _omitFieldNames ? '' : 'maxNumImages')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitializeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitializeRequest copyWith(void Function(InitializeRequest) updates) =>
      super.copyWith((message) => updates(message as InitializeRequest))
          as InitializeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InitializeRequest create() => InitializeRequest._();
  @$core.override
  InitializeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InitializeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InitializeRequest>(create);
  static InitializeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get backend => $_getSZ(1);
  @$pb.TagNumber(2)
  set backend($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBackend() => $_has(1);
  @$pb.TagNumber(2)
  void clearBackend() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get enableVision => $_getBF(3);
  @$pb.TagNumber(4)
  set enableVision($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEnableVision() => $_has(3);
  @$pb.TagNumber(4)
  void clearEnableVision() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxNumImages => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxNumImages($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxNumImages() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxNumImages() => $_clearField(5);
}

class InitializeResponse extends $pb.GeneratedMessage {
  factory InitializeResponse({
    $core.bool? success,
    $core.String? error,
    $core.String? modelInfo,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (error != null) result.error = error;
    if (modelInfo != null) result.modelInfo = modelInfo;
    return result;
  }

  InitializeResponse._();

  factory InitializeResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InitializeResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InitializeResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'error')
    ..aOS(3, _omitFieldNames ? '' : 'modelInfo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitializeResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitializeResponse copyWith(void Function(InitializeResponse) updates) =>
      super.copyWith((message) => updates(message as InitializeResponse))
          as InitializeResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InitializeResponse create() => InitializeResponse._();
  @$core.override
  InitializeResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InitializeResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InitializeResponse>(create);
  static InitializeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get error => $_getSZ(1);
  @$pb.TagNumber(2)
  set error($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelInfo => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelInfo($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelInfo() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelInfo() => $_clearField(3);
}

class CreateConversationRequest extends $pb.GeneratedMessage {
  factory CreateConversationRequest({
    $core.String? systemMessage,
    SamplerConfig? samplerConfig,
  }) {
    final result = create();
    if (systemMessage != null) result.systemMessage = systemMessage;
    if (samplerConfig != null) result.samplerConfig = samplerConfig;
    return result;
  }

  CreateConversationRequest._();

  factory CreateConversationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateConversationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateConversationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'systemMessage')
    ..aOM<SamplerConfig>(2, _omitFieldNames ? '' : 'samplerConfig',
        subBuilder: SamplerConfig.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateConversationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateConversationRequest copyWith(
          void Function(CreateConversationRequest) updates) =>
      super.copyWith((message) => updates(message as CreateConversationRequest))
          as CreateConversationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateConversationRequest create() => CreateConversationRequest._();
  @$core.override
  CreateConversationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateConversationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateConversationRequest>(create);
  static CreateConversationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get systemMessage => $_getSZ(0);
  @$pb.TagNumber(1)
  set systemMessage($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSystemMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearSystemMessage() => $_clearField(1);

  @$pb.TagNumber(2)
  SamplerConfig get samplerConfig => $_getN(1);
  @$pb.TagNumber(2)
  set samplerConfig(SamplerConfig value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSamplerConfig() => $_has(1);
  @$pb.TagNumber(2)
  void clearSamplerConfig() => $_clearField(2);
  @$pb.TagNumber(2)
  SamplerConfig ensureSamplerConfig() => $_ensure(1);
}

class SamplerConfig extends $pb.GeneratedMessage {
  factory SamplerConfig({
    $core.int? topK,
    $core.double? topP,
    $core.double? temperature,
  }) {
    final result = create();
    if (topK != null) result.topK = topK;
    if (topP != null) result.topP = topP;
    if (temperature != null) result.temperature = temperature;
    return result;
  }

  SamplerConfig._();

  factory SamplerConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SamplerConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SamplerConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'topK')
    ..aD(2, _omitFieldNames ? '' : 'topP', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SamplerConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SamplerConfig copyWith(void Function(SamplerConfig) updates) =>
      super.copyWith((message) => updates(message as SamplerConfig))
          as SamplerConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SamplerConfig create() => SamplerConfig._();
  @$core.override
  SamplerConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SamplerConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SamplerConfig>(create);
  static SamplerConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get topK => $_getIZ(0);
  @$pb.TagNumber(1)
  set topK($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTopK() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopK() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get topP => $_getN(1);
  @$pb.TagNumber(2)
  set topP($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTopP() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopP() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get temperature => $_getN(2);
  @$pb.TagNumber(3)
  set temperature($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTemperature() => $_has(2);
  @$pb.TagNumber(3)
  void clearTemperature() => $_clearField(3);
}

class CreateConversationResponse extends $pb.GeneratedMessage {
  factory CreateConversationResponse({
    $core.String? conversationId,
    $core.String? error,
  }) {
    final result = create();
    if (conversationId != null) result.conversationId = conversationId;
    if (error != null) result.error = error;
    return result;
  }

  CreateConversationResponse._();

  factory CreateConversationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateConversationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateConversationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOS(2, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateConversationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateConversationResponse copyWith(
          void Function(CreateConversationResponse) updates) =>
      super.copyWith(
              (message) => updates(message as CreateConversationResponse))
          as CreateConversationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateConversationResponse create() => CreateConversationResponse._();
  @$core.override
  CreateConversationResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateConversationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateConversationResponse>(create);
  static CreateConversationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get error => $_getSZ(1);
  @$pb.TagNumber(2)
  set error($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => $_clearField(2);
}

class ChatRequest extends $pb.GeneratedMessage {
  factory ChatRequest({
    $core.String? conversationId,
    $core.String? text,
  }) {
    final result = create();
    if (conversationId != null) result.conversationId = conversationId;
    if (text != null) result.text = text;
    return result;
  }

  ChatRequest._();

  factory ChatRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatRequest copyWith(void Function(ChatRequest) updates) =>
      super.copyWith((message) => updates(message as ChatRequest))
          as ChatRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatRequest create() => ChatRequest._();
  @$core.override
  ChatRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatRequest>(create);
  static ChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);
}

class ChatWithImageRequest extends $pb.GeneratedMessage {
  factory ChatWithImageRequest({
    $core.String? conversationId,
    $core.String? text,
    $core.List<$core.int>? image,
  }) {
    final result = create();
    if (conversationId != null) result.conversationId = conversationId;
    if (text != null) result.text = text;
    if (image != null) result.image = image;
    return result;
  }

  ChatWithImageRequest._();

  factory ChatWithImageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatWithImageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatWithImageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'image', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatWithImageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatWithImageRequest copyWith(void Function(ChatWithImageRequest) updates) =>
      super.copyWith((message) => updates(message as ChatWithImageRequest))
          as ChatWithImageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatWithImageRequest create() => ChatWithImageRequest._();
  @$core.override
  ChatWithImageRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatWithImageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatWithImageRequest>(create);
  static ChatWithImageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get image => $_getN(2);
  @$pb.TagNumber(3)
  set image($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasImage() => $_has(2);
  @$pb.TagNumber(3)
  void clearImage() => $_clearField(3);
}

class ChatResponse extends $pb.GeneratedMessage {
  factory ChatResponse({
    $core.String? text,
    $core.bool? done,
    $core.String? error,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (done != null) result.done = done;
    if (error != null) result.error = error;
    return result;
  }

  ChatResponse._();

  factory ChatResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'done')
    ..aOS(3, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatResponse copyWith(void Function(ChatResponse) updates) =>
      super.copyWith((message) => updates(message as ChatResponse))
          as ChatResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatResponse create() => ChatResponse._();
  @$core.override
  ChatResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatResponse>(create);
  static ChatResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get done => $_getBF(1);
  @$pb.TagNumber(2)
  set done($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDone() => $_has(1);
  @$pb.TagNumber(2)
  void clearDone() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
}

class CloseConversationRequest extends $pb.GeneratedMessage {
  factory CloseConversationRequest({
    $core.String? conversationId,
  }) {
    final result = create();
    if (conversationId != null) result.conversationId = conversationId;
    return result;
  }

  CloseConversationRequest._();

  factory CloseConversationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CloseConversationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CloseConversationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseConversationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseConversationRequest copyWith(
          void Function(CloseConversationRequest) updates) =>
      super.copyWith((message) => updates(message as CloseConversationRequest))
          as CloseConversationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CloseConversationRequest create() => CloseConversationRequest._();
  @$core.override
  CloseConversationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CloseConversationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CloseConversationRequest>(create);
  static CloseConversationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => $_clearField(1);
}

class CloseConversationResponse extends $pb.GeneratedMessage {
  factory CloseConversationResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  CloseConversationResponse._();

  factory CloseConversationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CloseConversationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CloseConversationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseConversationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseConversationResponse copyWith(
          void Function(CloseConversationResponse) updates) =>
      super.copyWith((message) => updates(message as CloseConversationResponse))
          as CloseConversationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CloseConversationResponse create() => CloseConversationResponse._();
  @$core.override
  CloseConversationResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CloseConversationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CloseConversationResponse>(create);
  static CloseConversationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class ShutdownRequest extends $pb.GeneratedMessage {
  factory ShutdownRequest() => create();

  ShutdownRequest._();

  factory ShutdownRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ShutdownRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ShutdownRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShutdownRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShutdownRequest copyWith(void Function(ShutdownRequest) updates) =>
      super.copyWith((message) => updates(message as ShutdownRequest))
          as ShutdownRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ShutdownRequest create() => ShutdownRequest._();
  @$core.override
  ShutdownRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ShutdownRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ShutdownRequest>(create);
  static ShutdownRequest? _defaultInstance;
}

class ShutdownResponse extends $pb.GeneratedMessage {
  factory ShutdownResponse({
    $core.bool? success,
  }) {
    final result = create();
    if (success != null) result.success = success;
    return result;
  }

  ShutdownResponse._();

  factory ShutdownResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ShutdownResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ShutdownResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShutdownResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ShutdownResponse copyWith(void Function(ShutdownResponse) updates) =>
      super.copyWith((message) => updates(message as ShutdownResponse))
          as ShutdownResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ShutdownResponse create() => ShutdownResponse._();
  @$core.override
  ShutdownResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ShutdownResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ShutdownResponse>(create);
  static ShutdownResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);
}

class HealthCheckRequest extends $pb.GeneratedMessage {
  factory HealthCheckRequest() => create();

  HealthCheckRequest._();

  factory HealthCheckRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HealthCheckRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HealthCheckRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckRequest copyWith(void Function(HealthCheckRequest) updates) =>
      super.copyWith((message) => updates(message as HealthCheckRequest))
          as HealthCheckRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HealthCheckRequest create() => HealthCheckRequest._();
  @$core.override
  HealthCheckRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HealthCheckRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HealthCheckRequest>(create);
  static HealthCheckRequest? _defaultInstance;
}

class HealthCheckResponse extends $pb.GeneratedMessage {
  factory HealthCheckResponse({
    $core.bool? healthy,
    $core.String? status,
  }) {
    final result = create();
    if (healthy != null) result.healthy = healthy;
    if (status != null) result.status = status;
    return result;
  }

  HealthCheckResponse._();

  factory HealthCheckResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HealthCheckResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HealthCheckResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'litertlm'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'healthy')
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HealthCheckResponse copyWith(void Function(HealthCheckResponse) updates) =>
      super.copyWith((message) => updates(message as HealthCheckResponse))
          as HealthCheckResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HealthCheckResponse create() => HealthCheckResponse._();
  @$core.override
  HealthCheckResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HealthCheckResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HealthCheckResponse>(create);
  static HealthCheckResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get healthy => $_getBF(0);
  @$pb.TagNumber(1)
  set healthy($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHealthy() => $_has(0);
  @$pb.TagNumber(1)
  void clearHealthy() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
