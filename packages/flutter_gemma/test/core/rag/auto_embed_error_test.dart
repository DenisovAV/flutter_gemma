import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/registry/embedding_registry.dart';

void main() {
  setUp(() => EmbeddingRegistry.instance.reset());

  test('embedding registry has no backends until one is registered', () {
    expect(EmbeddingRegistry.instance.hasAny, isFalse);
  });

  test(
      'requireEmbeddingBackend throws a StateError about the missing embedding backend when none registered',
      () {
    expect(
      () => requireEmbeddingBackend(),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('embedding backend'))),
    );
  });
}
