// The ONNX HuggingFace resolver reserves the ModelFileType.onnx slot so
// resolveHuggingFace(...) gives a clear "not implemented yet" instead of
// core's generic "no resolver registered". Directory-based genai_config
// resolution is a follow-up; until then resolve() throws.

import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart'
    show OnnxHuggingFaceResolver;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = OnnxHuggingFaceResolver();

  test('canResolve claims exactly ModelFileType.onnx (never a null hint)', () {
    expect(
      resolver.canResolve('org/repo', fileType: ModelFileType.onnx),
      isTrue,
    );
    // Every OTHER declared file type must NOT match, so the stub can never
    // shadow another engine's resolver. Iterating ModelFileType.values keeps
    // this exhaustive if a new value is ever added.
    for (final t in ModelFileType.values) {
      if (t == ModelFileType.onnx) continue;
      expect(
        resolver.canResolve('org/repo', fileType: t),
        isFalse,
        reason: '$t',
      );
    }
    // A bare hint must NOT match — otherwise resolveHuggingFace(repo) with no
    // fileType would route by registration order.
    expect(resolver.canResolve('org/repo'), isFalse);
  });

  test('resolve throws UnimplementedError naming the repo', () {
    expect(
      () => resolver.resolve('onnx-community/Qwen2.5-0.5B-Instruct'),
      throwsA(
        isA<UnimplementedError>().having(
          (e) => e.message,
          'message',
          contains('onnx-community/Qwen2.5-0.5B-Instruct'),
        ),
      ),
    );
  });

  test('name and priority are stable', () {
    expect(resolver.name, 'onnx-huggingface');
    expect(resolver.priority, 0);
  });
}
