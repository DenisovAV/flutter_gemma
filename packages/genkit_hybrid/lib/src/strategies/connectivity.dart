import '../routing_context.dart';
import '../routing_strategy.dart';

/// Routes by network availability. The app supplies [isOnline]; the package
/// depends on no connectivity SDK.
class ConnectivityStrategy implements RoutingStrategy {
  ConnectivityStrategy({
    required bool Function() isOnline,
    required String online,
    required String offline,
  })  : _isOnline = isOnline,
        _online = online,
        _offline = offline;

  final bool Function() _isOnline;
  final String _online;
  final String _offline;

  @override
  List<String> route(RoutingContext context) =>
      [_isOnline() ? _online : _offline];
}
