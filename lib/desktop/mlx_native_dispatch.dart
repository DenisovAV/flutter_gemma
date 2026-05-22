import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

abstract interface class MlxDispatching {
  Map<String, Object?> invoke(String operation, Map<String, Object?> payload);

  bool get isBlockingInvoke => true;
}

typedef _DispatchNative = Pointer<Utf8> Function(
  Pointer<Utf8> op,
  Pointer<Utf8> json,
);
typedef _DispatchDart = Pointer<Utf8> Function(
  Pointer<Utf8> op,
  Pointer<Utf8> json,
);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

final class MlxNativeDispatcher implements MlxDispatching {
  MlxNativeDispatcher();

  DynamicLibrary? _lib;
  _DispatchDart? _dispatch;
  _FreeDart? _free;

  @override
  bool get isBlockingInvoke => true;

  static bool isAvailable() {
    if (!Platform.isMacOS) {
      return false;
    }
    try {
      final lib = DynamicLibrary.process();
      lib.lookup<NativeFunction<Void Function()>>('flm_dispatch_json');
      lib.lookup<NativeFunction<Void Function(Pointer<Utf8>)>>(
        'flm_bridge_free_string',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _ensureLoaded() {
    if (_lib != null) {
      return;
    }
    if (!Platform.isMacOS) {
      throw UnsupportedError('Native MLX dispatch requires macOS.');
    }
    _lib = DynamicLibrary.process();
    _dispatch = _lib!.lookupFunction<_DispatchNative, _DispatchDart>(
      'flm_dispatch_json',
    );
    _free = _lib!.lookupFunction<_FreeNative, _FreeDart>(
      'flm_bridge_free_string',
    );
  }

  @override
  Map<String, Object?> invoke(String operation, Map<String, Object?> payload) {
    _ensureLoaded();
    final opPtr = operation.toNativeUtf8();
    final jsonPtr = jsonEncode(payload).toNativeUtf8();
    try {
      final outPtr = _dispatch!(opPtr, jsonPtr);
      if (outPtr.address == 0) {
        throw StateError('flm_dispatch_json returned null');
      }
      try {
        final jsonStr = outPtr.toDartString();
        final decoded = jsonDecode(jsonStr);
        if (decoded is! Map) {
          throw FormatException('Expected JSON object, got: $jsonStr');
        }
        return Map<String, Object?>.from(
          decoded.map((key, value) => MapEntry('$key', value)),
        );
      } finally {
        _free!(outPtr);
      }
    } finally {
      malloc.free(opPtr);
      malloc.free(jsonPtr);
    }
  }
}

final class RecordingMlxDispatcher implements MlxDispatching {
  RecordingMlxDispatcher();

  @override
  bool get isBlockingInvoke => false;

  final List<({String operation, Map<String, Object?> payload})> calls =
      <({String operation, Map<String, Object?> payload})>[];

  Map<String, Object?> Function(String op, Map<String, Object?> payload)?
      onInvoke;

  @override
  Map<String, Object?> invoke(String operation, Map<String, Object?> payload) {
    calls.add((
      operation: operation,
      payload: Map<String, Object?>.from(payload),
    ));
    return onInvoke?.call(operation, payload) ??
        <String, Object?>{
          'ok': false,
          'error': 'recording dispatcher: no handler configured',
        };
  }
}
