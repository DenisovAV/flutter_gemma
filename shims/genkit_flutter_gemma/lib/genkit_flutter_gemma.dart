/// `genkit_flutter_gemma` is now `genkit_flutter_edge_ai`.
///
/// This library only re-exports `package:genkit_flutter_edge_ai/genkit_flutter_edge_ai.dart`. Depend on
/// `genkit_flutter_edge_ai` instead, and replace `package:genkit_flutter_gemma/` with `package:genkit_flutter_edge_ai/` in
/// your imports.
@Deprecated(
  'genkit_flutter_gemma was renamed to genkit_flutter_edge_ai: depend on genkit_flutter_edge_ai and import '
  'package:genkit_flutter_edge_ai/genkit_flutter_edge_ai.dart '
  '(dart fix --apply does both on Flutter 3.47+).',
)
library;

export 'package:genkit_flutter_edge_ai/genkit_flutter_edge_ai.dart';
