class FunctionCall {
  const FunctionCall({
    required this.name,
    required this.args,
  });

  final String name;
  final Map<String, dynamic> args;
}
