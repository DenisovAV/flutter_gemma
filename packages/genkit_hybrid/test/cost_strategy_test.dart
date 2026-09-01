import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/src/routing_context.dart';
import 'package:genkit_hybrid/src/strategies/cost.dart';
import 'package:test/test.dart';

RoutingContext _ctx() => const RoutingContext(
  request: null,
  branchKeys: {'cloud', 'onDevice'},
  isStreaming: false,
);

void main() {
  test('budget available -> [premium, cheap]', () {
    final s = CostStrategy(
      budgetAvailable: () => true,
      premium: 'cloud',
      cheap: 'onDevice',
    );
    expect(s.route(_ctx()), ['cloud', 'onDevice']);
  });

  test('budget gone -> [cheap]', () {
    final s = CostStrategy(
      budgetAvailable: () => false,
      premium: 'cloud',
      cheap: 'onDevice',
    );
    expect(s.route(_ctx()), ['onDevice']);
  });

  test('the signal is read per call (dynamic)', () {
    var online = true;
    final s = CostStrategy(
      budgetAvailable: () => online,
      premium: 'cloud',
      cheap: 'onDevice',
    );
    expect(s.route(_ctx()), ['cloud', 'onDevice']);
    online = false;
    expect(s.route(_ctx()), ['onDevice']);
  });
}
