import 'package:genkit/genkit.dart';

/// What a [RoutingStrategy] sees when deciding where to route a request.
class RoutingContext {
  const RoutingContext({
    required this.request,
    required this.branchKeys,
    required this.isStreaming,
  });

  /// The incoming generate request (may be null, mirroring Genkit's contract).
  final ModelRequest? request;

  /// The set of available branch keys to choose from.
  final Set<String> branchKeys;

  /// Whether the caller requested a streaming response.
  final bool isStreaming;
}
