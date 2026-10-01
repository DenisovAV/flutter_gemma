import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:genkit/plugin.dart';

import 'backend_parse.dart';
import 'converters/request_converter.dart';
import 'converters/response_converter.dart';
import 'converters/tool_converter.dart';
import 'flutter_gemma_options.dart';
import 'flutter_gemma_runtime.dart';
import 'tool_choice_parse.dart';

/// Capabilities a flutter_gemma model advertises to Genkit. Shared by the
/// plugin's `list()` metadata AND the resolved [Model]'s `metadata` so the two
/// never drift (the resolved action previously carried no metadata, leaving its
/// supports empty at generate time). `constrained: false` — on-device Gemma has
/// no native schema-constrained decoder, so Genkit's instruction-injection
/// fallback drives JSON output (`output: ['text', 'json']`); we return the raw
/// model text and the framework's `extractJson` populates `response.output`.
const Map<String, dynamic> kFlutterGemmaModelSupports = {
  'multiturn': true,
  'media': true,
  'tools': true,
  'toolChoice': true,
  'systemRole': true,
  'constrained': false,
  'output': ['text', 'json'],
};

/// Creates a Genkit [Model] action backed by flutter_gemma inference.
///
/// Each call to the model's `fn`:
/// 1. Extracts options from `request.config`
/// 2. Gets (or reuses cached) [gemma.InferenceModel] via [runtime]
/// 3. Creates an [gemma.InferenceChat] session
/// 4. Converts Genkit messages → flutter_gemma messages
/// 5. Generates response (streaming or non-streaming)
/// 6. Converts response back to Genkit format
Model createFlutterGemmaModel({
  required String name,
  required gemma.ModelType modelType,
  required gemma.ModelFileType fileType,
  required FlutterGemmaRuntime runtime,
}) {
  // Cache the inference model to avoid recreating on every call.
  gemma.InferenceModel? cachedModel;
  int? cachedMaxTokens;
  bool? cachedSupportImage;
  bool? cachedSupportAudio;
  bool? cachedEnableSpeculativeDecoding;
  gemma.PreferredBackend? cachedPreferredBackend;
  gemma.PreferredBackend? cachedPreferredVisionBackend;
  gemma.PreferredBackend? cachedPreferredAudioBackend;

  // Future-chain lock: each caller awaits the previous one, ensuring
  // only one generation runs at a time against the native model.
  Future<void> lock = Future.value();

  return Model(
    name: name,
    metadata: {
      'model': {'supports': kFlutterGemmaModelSupports},
    },
    fn: (request, context) async {
      if (request == null) {
        throw GenkitException(
          'Model request cannot be null.',
          status: StatusCodes.INVALID_ARGUMENT,
        );
      }

      final prev = lock;
      final completer = Completer<void>();
      lock = completer.future;

      await prev;

      try {
        return await _executeGeneration(
          request: request,
          context: context,
          modelType: modelType,
          runtime: runtime,
          cachedModel: cachedModel,
          cachedMaxTokens: cachedMaxTokens,
          cachedSupportImage: cachedSupportImage,
          cachedSupportAudio: cachedSupportAudio,
          cachedEnableSpeculativeDecoding: cachedEnableSpeculativeDecoding,
          cachedPreferredBackend: cachedPreferredBackend,
          cachedPreferredVisionBackend: cachedPreferredVisionBackend,
          cachedPreferredAudioBackend: cachedPreferredAudioBackend,
          onModelCached:
              (
                model,
                maxTokens,
                supportImage,
                supportAudio,
                enableSpeculativeDecoding,
                preferredBackend,
                preferredVisionBackend,
                preferredAudioBackend,
              ) {
                cachedModel = model;
                cachedMaxTokens = maxTokens;
                cachedSupportImage = supportImage;
                cachedSupportAudio = supportAudio;
                cachedEnableSpeculativeDecoding = enableSpeculativeDecoding;
                cachedPreferredBackend = preferredBackend;
                cachedPreferredVisionBackend = preferredVisionBackend;
                cachedPreferredAudioBackend = preferredAudioBackend;
              },
        );
      } finally {
        completer.complete();
      }
    },
  );
}

/// Executes the generation logic, extracted for readability.
Future<ModelResponse> _executeGeneration({
  required ModelRequest request,
  required ActionFnArg<ModelResponseChunk, ModelRequest, void> context,
  required gemma.ModelType modelType,
  required FlutterGemmaRuntime runtime,
  required gemma.InferenceModel? cachedModel,
  required int? cachedMaxTokens,
  required bool? cachedSupportImage,
  required bool? cachedSupportAudio,
  required bool? cachedEnableSpeculativeDecoding,
  required gemma.PreferredBackend? cachedPreferredBackend,
  required gemma.PreferredBackend? cachedPreferredVisionBackend,
  required gemma.PreferredBackend? cachedPreferredAudioBackend,
  required void Function(
    gemma.InferenceModel,
    int,
    bool,
    bool,
    bool?,
    gemma.PreferredBackend?,
    gemma.PreferredBackend?,
    gemma.PreferredBackend?,
  )
  onModelCached,
}) async {
  // Parse config from the untyped Map.
  final configMap = request.config;
  final FlutterGemmaModelOptions? config;
  try {
    config = configMap != null
        ? FlutterGemmaModelOptions.fromJson(configMap)
        : null;
  } catch (e) {
    throw GenkitException(
      'Invalid model config: $e',
      status: StatusCodes.INVALID_ARGUMENT,
    );
  }

  final maxTokens = config?.maxTokens ?? 1024;
  final temperature = config?.temperature ?? 0.8;
  final topK = config?.topK ?? 1;
  final topP = config?.topP;
  final randomSeed = config?.randomSeed ?? 1;
  final supportImage = config?.supportImage ?? false;
  final supportAudio = config?.supportAudio ?? false;
  final isThinking = config?.isThinking ?? false;
  final enableSpeculativeDecoding = config?.enableSpeculativeDecoding;
  // Prefer the native top-level request.toolChoice (Genkit 0.15's standard
  // field) over the legacy config.toolChoice custom option. Fails loud on an
  // unrecognized value (see parseToolChoice) rather than silently defaulting
  // to auto — a 'none' typo must not quietly re-enable tools.
  final gemmaToolChoice = parseToolChoice(
    request.toolChoice ?? config?.toolChoice,
  );
  final systemInstruction =
      config?.systemInstruction ?? extractSystemInstruction(request.messages);
  final maxFunctionBufferLength = config?.maxFunctionBufferLength;
  final preferredBackend = parsePreferredBackend(
    config?.preferredBackend,
    field: 'preferredBackend',
  );
  final preferredVisionBackend = parsePreferredBackend(
    config?.preferredVisionBackend,
    field: 'preferredVisionBackend',
  );
  final preferredAudioBackend = parsePreferredBackend(
    config?.preferredAudioBackend,
    field: 'preferredAudioBackend',
  );

  // Get or create InferenceModel (cached if params match).
  final needsNewModel =
      cachedModel == null ||
      cachedMaxTokens != maxTokens ||
      cachedSupportImage != supportImage ||
      cachedSupportAudio != supportAudio ||
      cachedEnableSpeculativeDecoding != enableSpeculativeDecoding ||
      cachedPreferredBackend != preferredBackend ||
      cachedPreferredVisionBackend != preferredVisionBackend ||
      cachedPreferredAudioBackend != preferredAudioBackend;

  gemma.InferenceModel model;
  if (needsNewModel) {
    model = await runtime.getActiveModel(
      maxTokens: maxTokens,
      supportImage: supportImage,
      supportAudio: supportAudio,
      enableSpeculativeDecoding: enableSpeculativeDecoding,
      preferredBackend: preferredBackend,
      preferredVisionBackend: preferredVisionBackend,
      preferredAudioBackend: preferredAudioBackend,
    );
    onModelCached(
      model,
      maxTokens,
      supportImage,
      supportAudio,
      enableSpeculativeDecoding,
      preferredBackend,
      preferredVisionBackend,
      preferredAudioBackend,
    );
  } else {
    model = cachedModel;
  }

  // Convert tools.
  final gemmaTools = convertTools(request.tools);
  final supportsFunctionCalls = gemmaTools.isNotEmpty;

  // Create chat session.
  final chat = await model.createChat(
    temperature: temperature,
    randomSeed: randomSeed,
    topK: topK,
    topP: topP,
    supportImage: supportImage,
    supportAudio: supportAudio,
    tools: gemmaTools,
    supportsFunctionCalls: supportsFunctionCalls,
    isThinking: isThinking,
    modelType: modelType,
    toolChoice: gemmaToolChoice,
    systemInstruction: systemInstruction,
    maxFunctionBufferLength: maxFunctionBufferLength,
  );

  // Convert and add messages.
  final gemmaMessages = await convertMessages(request.messages);
  if (gemmaMessages.isEmpty) {
    throw GenkitException(
      'No convertible messages in request. System messages alone are not '
      'sufficient — at least one user or model message is required.',
      status: StatusCodes.INVALID_ARGUMENT,
    );
  }
  for (final msg in gemmaMessages) {
    await chat.addQueryChunk(msg);
  }

  // Generate response.
  final stopwatch = Stopwatch()..start();
  if (context.streamingRequested) {
    return _generateStreaming(
      chat,
      context.sendChunk,
      stopwatch,
      gemmaMessages,
    );
  } else {
    return _generateBlocking(chat, stopwatch, gemmaMessages);
  }
}

/// Generates a blocking (non-streaming) response.
Future<ModelResponse> _generateBlocking(
  gemma.InferenceChat chat,
  Stopwatch stopwatch,
  List<gemma.Message> gemmaMessages,
) async {
  final response = await chat.generateChatResponse();
  final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

  String fullText = '';
  String outputText = '';
  List<gemma.FunctionCallResponse>? functionCalls;
  String? reasoningText;

  switch (response) {
    case gemma.TextResponse(:final token):
      fullText = token;
      outputText = token;
    case gemma.FunctionCallResponse(:final name, :final args):
      functionCalls = [gemma.FunctionCallResponse(name: name, args: args)];
    case gemma.ParallelFunctionCallResponse(:final calls):
      functionCalls = calls;
    case gemma.ThinkingResponse(:final content):
      reasoningText = content;
      outputText = content;
  }

  final usage = await _computeUsage(
    chat: chat,
    gemmaMessages: gemmaMessages,
    outputText: outputText,
  );

  return convertFinalResponse(
    fullText,
    functionCalls: functionCalls,
    reasoningText: reasoningText,
    latencyMs: latencyMs,
    usage: usage,
  );
}

/// Generates a streaming response, sending chunks via [sendChunk].
Future<ModelResponse> _generateStreaming(
  gemma.InferenceChat chat,
  void Function(ModelResponseChunk) sendChunk,
  Stopwatch stopwatch,
  List<gemma.Message> gemmaMessages,
) async {
  final fullText = StringBuffer();
  final reasoningText = StringBuffer();
  final functionCalls = <gemma.FunctionCallResponse>[];

  await for (final chunk in chat.generateChatResponseAsync()) {
    sendChunk(convertStreamChunk(chunk));

    switch (chunk) {
      case gemma.TextResponse(:final token):
        fullText.write(token);
      case gemma.FunctionCallResponse(:final name, :final args):
        functionCalls.add(gemma.FunctionCallResponse(name: name, args: args));
      case gemma.ParallelFunctionCallResponse(:final calls):
        functionCalls.addAll(calls);
      case gemma.ThinkingResponse(:final content):
        reasoningText.write(content);
    }
  }

  final responseText = fullText.isNotEmpty
      ? fullText.toString()
      : reasoningText.toString();
  final usage = await _computeUsage(
    chat: chat,
    gemmaMessages: gemmaMessages,
    outputText: responseText,
  );

  return convertFinalResponse(
    fullText.toString(),
    functionCalls: functionCalls.isNotEmpty ? functionCalls : null,
    reasoningText: reasoningText.isNotEmpty ? reasoningText.toString() : null,
    latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
    usage: usage,
  );
}

/// Computes token usage for the completed turn.
///
/// Ordering:
/// 1. Prefer [chat.session.getSessionMetrics] when it returns non-zero counts
///    (LiteRT-LM FFI engine, which includes system instructions and tools).
/// 2. Fall back to [chat.session.sizeInTokens] otherwise (MediaPipe engine where
///    metrics are empty).
///    NOTE: sizeInTokens covers only the converted message text and response text.
///    The system instruction, the tools prompt that InferenceChat injects, and
///    engine/prompt suffixes (e.g. /no_think) are not in it, so inputTokens
///    under-counts those requests compared to LiteRT-LM FFI.
/// 3. If token counting throws, return null so generation returns without usage
///    rather than failing a response that already succeeded.
Future<GenerationUsage?> _computeUsage({
  required gemma.InferenceChat chat,
  required List<gemma.Message> gemmaMessages,
  required String outputText,
}) async {
  try {
    final metrics = chat.session.getSessionMetrics();
    if (metrics.inputTokens > 0 ||
        metrics.outputTokens > 0 ||
        metrics.totalTokens > 0) {
      final input = metrics.inputTokens.toDouble();
      final output = metrics.outputTokens.toDouble();
      final total = (metrics.totalTokens > 0
              ? metrics.totalTokens
              : (metrics.inputTokens + metrics.outputTokens))
          .toDouble();
      return GenerationUsage(
        inputTokens: input,
        outputTokens: output,
        totalTokens: total,
      );
    }

    int inputTokens = 0;
    for (final msg in gemmaMessages) {
      if (msg.text.isNotEmpty) {
        inputTokens += await chat.session.sizeInTokens(msg.text);
      }
    }

    int outputTokens = 0;
    if (outputText.isNotEmpty) {
      outputTokens = await chat.session.sizeInTokens(outputText);
    }

    return GenerationUsage(
      inputTokens: inputTokens.toDouble(),
      outputTokens: outputTokens.toDouble(),
      totalTokens: (inputTokens + outputTokens).toDouble(),
    );
  } catch (_) {
    return null;
  }
}
