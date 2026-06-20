import '../routing_context.dart';
import '../routing_strategy.dart';

/// Picks a single branch using a developer-supplied function.
///
/// The universal escape hatch for any app-specific rule (privacy, cost,
/// user tier, etc.) that the package cannot compute itself.
///
/// Return an empty string to mean 'no decision' (useful inside [FirstMatch]).
class PreRoutingStrategy implements RoutingStrategy {
  PreRoutingStrategy(this._select);

  final String Function(RoutingContext context) _select;

  @override
  List<String> route(RoutingContext context) {
    final key = _select(context);
    return key.isEmpty ? const [] : [key];
  }
}
