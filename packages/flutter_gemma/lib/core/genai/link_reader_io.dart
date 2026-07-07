import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readFileUri(Uri uri) async {
  final path = uri.scheme == 'file' ? uri.toFilePath() : uri.path;
  return File(path).readAsBytes();
}
