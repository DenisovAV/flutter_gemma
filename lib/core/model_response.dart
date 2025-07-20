/// Base interface for model responses from InferenceChat
/// Can be either TextResponse or FunctionCallResponse
abstract class ModelResponse {
  const ModelResponse();
}

/// Text token during streaming
class TextResponse extends ModelResponse {
  final String token;
  
  const TextResponse(this.token);
  
  @override
  String toString() => 'TextResponse("$token")';
  
  @override
  bool operator ==(Object other) {
    return other is TextResponse && other.token == token;
  }
  
  @override
  int get hashCode => token.hashCode;
}

class FunctionCallResponse extends ModelResponse {
  const FunctionCallResponse({
    required this.name,
    required this.args,
  });

  final String name;
  final Map<String, dynamic> args;
}
