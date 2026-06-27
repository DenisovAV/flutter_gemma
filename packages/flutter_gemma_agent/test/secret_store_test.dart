import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecretStore', () {
    test('set / get / has by skill name', () {
      final store = SecretStore();
      expect(store.has('weather'), isFalse);
      expect(store.get('weather'), isNull);

      store.set('weather', 'sk-123');
      expect(store.get('weather'), 'sk-123');
      expect(store.has('weather'), isTrue);
    });

    test('empty secret is not considered "has"', () {
      final store = SecretStore()..set('x', '');
      expect(store.has('x'), isFalse);
    });

    test('set replaces existing value', () {
      final store = SecretStore()
        ..set('x', 'a')
        ..set('x', 'b');
      expect(store.get('x'), 'b');
    });

    test('remove and clear', () {
      final store = SecretStore()
        ..set('a', '1')
        ..set('b', '2');

      store.remove('a');
      expect(store.get('a'), isNull);
      expect(store.get('b'), '2');

      store.clear();
      expect(store.get('b'), isNull);
    });
  });
}
