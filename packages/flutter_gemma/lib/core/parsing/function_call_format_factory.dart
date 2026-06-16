import 'package:flutter_gemma/core/model.dart';

import 'deepseek_function_call_format.dart';
import 'function_call_format.dart';
import 'function_gemma_format.dart';
import 'json_function_call_format.dart';
import 'llama_function_call_format.dart';
import 'phi_function_call_format.dart';
import 'qwen_function_call_format.dart';
import 'sdk_passthrough_function_call_format.dart';

/// Factory for creating model-specific [FunctionCallFormat] instances.
class FunctionCallFormatFactory {
  static FunctionCallFormat create(ModelType? modelType) {
    return switch (modelType) {
      ModelType.functionGemma => FunctionGemmaCallFormat(),
      // Gemma 4: SDK parses native <|tool_call>...<tool_call|> tokens itself;
      // chat.dart reads structured tool_calls from session.lastRawResponse via
      // SdkResponseParser. Passthrough format reports "no calls in text".
      ModelType.gemma4 => SdkPassthroughFunctionCallFormat(),
      ModelType.qwen => QwenFunctionCallFormat(),
      ModelType.qwen3 => QwenFunctionCallFormat(),
      ModelType.deepSeek => DeepSeekFunctionCallFormat(),
      ModelType.llama => LlamaFunctionCallFormat(),
      ModelType.phi => PhiFunctionCallFormat(),
      // gemmaIt, hammer, general, and null all use JSON format
      _ => JsonFunctionCallFormat(),
    };
  }
}
