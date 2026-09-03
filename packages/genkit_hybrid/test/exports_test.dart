import 'package:genkit_hybrid/genkit_hybrid.dart';
import 'package:test/test.dart';

void main() {
  test('public API is exported', () {
    expect(kOnDevice, 'onDevice');
    expect(kCloud, 'cloud');
    expect(
      FallbackStrategy(['cloud']).route(
        const RoutingContext(
          request: null,
          branchKeys: {'cloud'},
          isStreaming: false,
        ),
      ),
      ['cloud'],
    );
    expect(PreRoutingStrategy((_) => 'cloud'), isA<RoutingStrategy>());
    expect(
      ConnectivityStrategy(
        isOnline: () => true,
        online: 'cloud',
        offline: 'onDevice',
      ),
      isA<RoutingStrategy>(),
    );
    expect(
      InputSizeStrategy(threshold: 1, small: 'a', large: 'b'),
      isA<RoutingStrategy>(),
    );
    expect(FirstMatch(const []), isA<RoutingStrategy>());
    expect(
      WithFallback(FallbackStrategy(['cloud']), fallbackOrder: const []),
      isA<RoutingStrategy>(),
    );
    expect(hybridModel, isNotNull);
    expect(hybridModelOnDeviceCloud, isNotNull);

    // new in 0.2.0
    expect(ModelCapability.vision, isNotNull);
    expect(
      CapabilityStrategy(supports: {'a': {}}).route(
        const RoutingContext(
          request: null,
          branchKeys: {'a'},
          isStreaming: false,
        ),
      ),
      ['a'],
    );
    expect(
      CostStrategy(budgetAvailable: () => true, premium: 'c', cheap: 'd').route(
        const RoutingContext(
          request: null,
          branchKeys: {'c', 'd'},
          isStreaming: false,
        ),
      ),
      ['c', 'd'],
    );
    expect(cascadeModel, isNotNull); // tear-off reference proves the export
  });
}
