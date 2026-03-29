class Tool {
  const Tool({
    required this.name,
    required this.description,
    this.parameters = const {},
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

/// Controls whether the model should call tools.
enum ToolChoice {
  /// Model decides whether to call a tool (default).
  auto,

  /// Model must respond with a function call.
  required,

  /// Model must NOT call any tools, even if tools are provided.
  none,
}
