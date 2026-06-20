import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart';

import 'routing_context.dart';
import 'routing_strategy.dart';

/// Whether [error] is a transient/availability failure that justifies trying
/// the next branch. Permanent errors (bad request, bad auth) must NOT trigger
/// fallback — the next branch would get the same bad request and also fail,
/// masking the real cause. Non-GenkitException throwables (network, timeout,
/// OOM) are treated as transient.
bool _isTransient(Object error) {
  if (error is! GenkitException) return true;
  switch (error.status) {
    case StatusCodes.UNAVAILABLE:
    case StatusCodes.DEADLINE_EXCEEDED:
    case StatusCodes.RESOURCE_EXHAUSTED:
    case StatusCodes.INTERNAL:
      return true;
    default:
      return false;
  }
}

/// Branch key for the on-device model in the binary façade.
const String kOnDevice = 'onDevice';

/// Branch key for the cloud model in the binary façade.
const String kCloud = 'cloud';

/// Builds a hybrid [Model] that routes each request to one of [branches]
/// according to [strategy]. The result is an ordinary [Model]: callers use it
/// via `ai.generate(model: theResult)` exactly like any other model.
///
/// The optional [name] is used as the returned [Model]'s name (and registry
/// key). Defaults to `'hybrid'` so existing call sites require no changes.
Model hybridModel({
  required Map<String, Model> branches,
  required RoutingStrategy strategy,
  String name = 'hybrid',
}) {
  if (branches.isEmpty) {
    throw ArgumentError.value(branches, 'branches', 'must not be empty');
  }
  final frozenBranches = Map<String, Model>.unmodifiable(branches);
  return Model(
    name: name,
    fn: (request, context) async {
      final order = strategy.route(RoutingContext(
        request: request,
        branchKeys: frozenBranches.keys.toSet(),
        isStreaming: context.streamingRequested,
      ));

      if (order.isEmpty) {
        throw GenkitException(
          'RoutingStrategy returned no branch to route to.',
          status: StatusCodes.FAILED_PRECONDITION,
        );
      }
      for (final key in order) {
        if (!frozenBranches.containsKey(key)) {
          throw GenkitException(
            'RoutingStrategy returned unknown branch key "$key". '
            'Available: ${frozenBranches.keys.join(', ')}.',
            status: StatusCodes.FAILED_PRECONDITION,
          );
        }
      }

      // Non-streaming: try each branch, fall back on transient failure.
      if (!context.streamingRequested) {
        for (var i = 0; i < order.length; i++) {
          final key = order[i];
          final isLast = i == order.length - 1;
          try {
            return await frozenBranches[key]!.fn(request, context);
          } catch (e) {
            if (isLast || !_isTransient(e)) rethrow;
          }
        }
        throw StateError('unreachable'); // loop always returns or rethrows.
      }

      // Streaming: fall back ONLY before the first token is emitted.
      for (var i = 0; i < order.length; i++) {
        final key = order[i];
        final isLast = i == order.length - 1;
        var firstTokenSent = false;
        final wrappedContext = (
          streamingRequested: true,
          sendChunk: (ModelResponseChunk chunk) {
            firstTokenSent = true;
            context.sendChunk(chunk);
          },
          context: context.context,
          inputStream: context.inputStream,
          // Safe because Model fixes Init = void; revisit if hybridModel is
          // ever generalized to a non-void Init.
          init: null,
        );
        try {
          return await frozenBranches[key]!.fn(request, wrappedContext);
        } catch (e) {
          // Once a token is out, we cannot re-route — propagate.
          // Before the first token, fall back on transient failures only.
          if (firstTokenSent || isLast || !_isTransient(e)) rethrow;
        }
      }
      throw StateError('unreachable'); // loop always returns or rethrows.
    },
  );
}

/// Binary façade over [hybridModel] for the common on-device/cloud case.
///
/// The optional [name] is forwarded to [hybridModel] as the returned [Model]'s
/// name (and registry key). Defaults to `'hybrid'`.
Model hybridModelOnDeviceCloud({
  required Model onDevice,
  required Model cloud,
  required RoutingStrategy strategy,
  String name = 'hybrid',
}) {
  return hybridModel(
    branches: {kOnDevice: onDevice, kCloud: cloud},
    strategy: strategy,
    name: name,
  );
}
