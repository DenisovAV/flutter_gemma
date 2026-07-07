import 'dart:typed_data';

/// Web: no filesystem. Callers must pass DataPart bytes, not file:// links.
Future<Uint8List> readFileUri(Uri uri) => throw UnimplementedError(
  'file:// links are not readable on web ($uri). '
  'Resolve to DataPart bytes before sending.',
);
