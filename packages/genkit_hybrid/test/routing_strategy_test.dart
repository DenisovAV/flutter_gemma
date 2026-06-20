import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/src/routing_context.dart';
import 'package:genkit_hybrid/src/routing_strategy.dart';
import 'package:genkit_hybrid/src/strategies/connectivity.dart';
import 'package:genkit_hybrid/src/strategies/fallback.dart';
import 'package:genkit_hybrid/src/strategies/first_match.dart';
import 'package:genkit_hybrid/src/strategies/input_size.dart';
import 'package:genkit_hybrid/src/strategies/pre_routing.dart';
import 'package:genkit_hybrid/src/strategies/with_fallback.dart';
import 'package:test/test.dart';

void main() {
  test('RoutingContext exposes request, branchKeys and isStreaming', () {
    final request = ModelRequest(messages: []);
    const ctx = RoutingContext(
      request: null,
      branchKeys: {'onDevice', 'cloud'},
      isStreaming: true,
    );
    expect(ctx.branchKeys, contains('cloud'));
    expect(ctx.isStreaming, isTrue);
    expect(ctx.request, isNull);

    final ctx2 = RoutingContext(
      request: request,
      branchKeys: const {'a'},
      isStreaming: false,
    );
    expect(ctx2.request, same(request));
    expect(ctx2.isStreaming, isFalse);
  });

  test('RoutingStrategy can be implemented and returns ordered keys', () {
    final s = _ConstStrategy(['cloud', 'onDevice']);
    const ctx = RoutingContext(
      request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false,
    );
    expect(s.route(ctx), ['cloud', 'onDevice']);
  });

  test('PreRoutingStrategy wraps a function and returns single key', () {
    final s = PreRoutingStrategy((c) => c.isStreaming ? 'cloud' : 'onDevice');
    const stream = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: true);
    const block = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(stream), ['cloud']);
    expect(s.route(block), ['onDevice']);
  });

  test('FallbackStrategy returns its fixed order regardless of context', () {
    final s = FallbackStrategy(['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']);
  });

  test('ConnectivityStrategy routes by online/offline', () {
    var online = true;
    final s = ConnectivityStrategy(
      isOnline: () => online,
      online: 'cloud',
      offline: 'onDevice',
    );
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud']);
    online = false;
    expect(s.route(ctx), ['onDevice']);
  });

  test('InputSizeStrategy routes by total prompt char length', () {
    final s = InputSizeStrategy(threshold: 10, small: 'onDevice', large: 'cloud');
    final shortReq = ModelRequest(messages: [
      Message(role: Role.user, content: [TextPart(text: 'hi')]),
    ]);
    final longReq = ModelRequest(messages: [
      Message(role: Role.user, content: [TextPart(text: 'this is a long prompt')]),
    ]);
    RoutingContext ctx(ModelRequest r) =>
        RoutingContext(request: r, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx(shortReq)), ['onDevice']);
    expect(s.route(ctx(longReq)), ['cloud']);
  });

  test('InputSizeStrategy treats null request as size 0 (small)', () {
    final s = InputSizeStrategy(threshold: 10, small: 'onDevice', large: 'cloud');
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice']);
  });

  test('FirstMatch returns first non-empty child result; skips empty', () {
    final s = FirstMatch([
      _ConstStrategy([]),            // no decision -> skipped
      _ConstStrategy(['cloud']),     // first match
      _ConstStrategy(['onDevice']),  // never reached
    ]);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud']);
  });

  test('FirstMatch returns empty when all children are empty', () {
    final s = FirstMatch([_ConstStrategy([]), _ConstStrategy([])]);
    const ctx = RoutingContext(request: null, branchKeys: {'cloud'}, isStreaming: false);
    expect(s.route(ctx), isEmpty);
  });

  test('WithFallback appends fallback tail to inner pick', () {
    final s = WithFallback(_ConstStrategy(['cloud']), fallbackOrder: ['onDevice']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud', 'onDevice']);
  });

  test('WithFallback de-dupes keys already chosen by inner strategy', () {
    final s = WithFallback(_ConstStrategy(['onDevice']), fallbackOrder: ['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']);
  });

  test('WithFallback returns just the tail when inner is empty', () {
    final s = WithFallback(_ConstStrategy([]), fallbackOrder: ['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']);
  });

  test('FallbackStrategy ignores later mutation of the input list', () {
    final input = ['onDevice', 'cloud'];
    final s = FallbackStrategy(input);
    input.add('mutated'); // mutate AFTER construction
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']); // unaffected by mutation
  });

  test('FallbackStrategy returns an unmodifiable list', () {
    final s = FallbackStrategy(['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(() => s.route(ctx).add('x'), throwsUnsupportedError);
  });

  test('FallbackStrategy throws on empty order (release-safe, not assert)', () {
    expect(() => FallbackStrategy([]), throwsArgumentError);
  });

  test('WithFallback ignores later mutation of fallbackOrder', () {
    final tail = ['onDevice'];
    final s = WithFallback(_ConstStrategy(['cloud']), fallbackOrder: tail);
    tail.add('mutated'); // mutate AFTER construction
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud', 'onDevice']); // unaffected
  });

  test('PreRoutingStrategy treats empty-string return as no decision', () {
    final s = PreRoutingStrategy((_) => '');
    const ctx = RoutingContext(request: null, branchKeys: {'cloud'}, isStreaming: false);
    expect(s.route(ctx), isEmpty);
  });

  test('InputSizeStrategy: size equal to threshold routes to small', () {
    final s = InputSizeStrategy(threshold: 10, small: 'onDevice', large: 'cloud');
    final exactReq = ModelRequest(messages: [
      Message(role: Role.user, content: [TextPart(text: '1234567890')]), // exactly 10 chars
    ]);
    final ctx = RoutingContext(request: exactReq, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice']); // == threshold -> small
  });
}

class _ConstStrategy implements RoutingStrategy {
  _ConstStrategy(this.keys);
  final List<String> keys;
  @override
  List<String> route(RoutingContext context) => keys;
}
