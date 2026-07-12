import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readFileUri(Uri uri) => File.fromUri(uri).readAsBytes();
