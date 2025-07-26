import 'package:flutter_gemma/core/model_response.dart';

void main() {
  final response = FunctionCallResponse(name: 'test', args: {});
  print('Function name: ${response.name}');
}
