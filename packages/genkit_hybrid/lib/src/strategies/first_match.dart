import '../routing_context.dart';
import '../routing_strategy.dart';

/// Tries each child strategy in order; the first to return a non-empty result
/// wins. Returns empty if no child decides (which is a config error at the top
/// level, but valid when nested inside another combinator).
class FirstMatch implements RoutingStrategy {
  FirstMatch(this._children);

  final List<RoutingStrategy> _children;

  @override
  List<String> route(RoutingContext context) {
    for (final child in _children) {
      final result = child.route(context);
      if (result.isNotEmpty) return result;
    }
    return const [];
  }
}
