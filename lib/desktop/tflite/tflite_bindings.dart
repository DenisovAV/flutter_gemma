import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI struct matching C `TfLiteXNNPackDelegateOptions`.
final class TfLiteXNNPackDelegateOptions extends Struct {
  @Int32()
  external int numThreads;

  @Uint32()
  external int runtimeFlags;

  @Uint32()
  external int flags;

  external Pointer<Void> weightsCache;

  @Bool()
  external bool handleVariableOps;

  external Pointer<Utf8> weightCacheFilePath;

  @Int32()
  external int weightCacheFileDescriptor;

  external Pointer<Void> weightCacheProvider;

  @Bool()
  external bool weightCacheLockMemory;
}

/// Raw FFI bindings to the TensorFlow Lite C API.
///
/// Loads `libtensorflowlite_c` from the app bundle and exposes the minimal
/// set of functions needed for embedding model inference.
class TfLiteBindings {
  TfLiteBindings._(this._lib);

  final DynamicLibrary _lib;

  static TfLiteBindings? _instance;

  /// Load TFLite C library bundled by Native Assets (hook/build.dart).
  ///
  /// `tensorflowlite_c.{dll,so,dylib}` is registered as a Native Assets
  /// `CodeAsset` and placed by the Flutter tool — on macOS as a
  /// `tensorflowlite_c.framework` bundle inside `Contents/Frameworks/`,
  /// on Windows as a `.dll` next to `<runner>.exe`, on Linux as a `.so`
  /// in `<runner>/lib/`. `dlopen`/`LoadLibrary` resolves the platform-
  /// canonical basename via the runtime's library search path (rpath on
  /// macOS, the exe's directory on Windows, `LD_LIBRARY_PATH` / runpath
  /// on Linux). [libraryPath] kept for unit tests.
  static TfLiteBindings load({String? libraryPath}) {
    if (_instance != null) return _instance!;

    final lib = libraryPath != null
        ? DynamicLibrary.open(libraryPath)
        : DynamicLibrary.open(_platformLibraryName());
    _instance = TfLiteBindings._(lib);
    return _instance!;
  }

  static String _platformLibraryName() {
    if (Platform.isMacOS) {
      // Native Assets wraps macOS dylibs into versioned .framework bundles.
      // Resolve to the framework's executable name; dyld locates it via
      // the runner's rpath that Flutter sets up.
      return 'tensorflowlite_c.framework/tensorflowlite_c';
    }
    if (Platform.isWindows) return 'tensorflowlite_c.dll';
    // Linux
    return 'libtensorflowlite_c.so';
  }

  // --- Model ---

  late final Pointer<Void> Function(Pointer<Utf8> modelPath)
      tfLiteModelCreateFromFile = _lib
          .lookup<NativeFunction<Pointer<Void> Function(Pointer<Utf8>)>>(
              'TfLiteModelCreateFromFile')
          .asFunction();

  late final void Function(Pointer<Void> model) tfLiteModelDelete = _lib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>('TfLiteModelDelete')
      .asFunction();

  // --- Interpreter Options ---

  late final Pointer<Void> Function() tfLiteInterpreterOptionsCreate = _lib
      .lookup<NativeFunction<Pointer<Void> Function()>>(
          'TfLiteInterpreterOptionsCreate')
      .asFunction();

  late final void Function(Pointer<Void> options)
      tfLiteInterpreterOptionsDelete = _lib
          .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
              'TfLiteInterpreterOptionsDelete')
          .asFunction();

  late final void Function(Pointer<Void> options, int numThreads)
      tfLiteInterpreterOptionsSetNumThreads = _lib
          .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
              'TfLiteInterpreterOptionsSetNumThreads')
          .asFunction();

  // --- Interpreter ---

  late final Pointer<Void> Function(Pointer<Void> model, Pointer<Void> options)
      tfLiteInterpreterCreate = _lib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(
                      Pointer<Void>, Pointer<Void>)>>('TfLiteInterpreterCreate')
          .asFunction();

  late final Pointer<Void> Function(Pointer<Void> model, Pointer<Void> options)
      tfLiteInterpreterCreateWithSelectedOps = _lib
          .lookup<
              NativeFunction<
                  Pointer<Void> Function(Pointer<Void>,
                      Pointer<Void>)>>('TfLiteInterpreterCreateWithSelectedOps')
          .asFunction();

  late final void Function(Pointer<Void> interpreter) tfLiteInterpreterDelete =
      _lib
          .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
              'TfLiteInterpreterDelete')
          .asFunction();

  late final int Function(Pointer<Void> interpreter)
      tfLiteInterpreterAllocateTensors = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
              'TfLiteInterpreterAllocateTensors')
          .asFunction();

  late final int Function(Pointer<Void> interpreter) tfLiteInterpreterInvoke =
      _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
              'TfLiteInterpreterInvoke')
          .asFunction();

  // --- Tensor Counts ---

  late final int Function(Pointer<Void> interpreter)
      tfLiteInterpreterGetInputTensorCount = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
              'TfLiteInterpreterGetInputTensorCount')
          .asFunction();

  late final int Function(Pointer<Void> interpreter)
      tfLiteInterpreterGetOutputTensorCount = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
              'TfLiteInterpreterGetOutputTensorCount')
          .asFunction();

  // --- Input/Output Tensors ---

  late final Pointer<Void> Function(Pointer<Void> interpreter, int inputIndex)
      tfLiteInterpreterGetInputTensor = _lib
          .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Int32)>>(
              'TfLiteInterpreterGetInputTensor')
          .asFunction();

  late final Pointer<Void> Function(Pointer<Void> interpreter, int outputIndex)
      tfLiteInterpreterGetOutputTensor = _lib
          .lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Int32)>>(
              'TfLiteInterpreterGetOutputTensor')
          .asFunction();

  // --- Tensor Data ---

  late final int Function(
          Pointer<Void> tensor, Pointer<Void> inputData, int inputDataSize)
      tfLiteTensorCopyFromBuffer = _lib
          .lookup<
              NativeFunction<
                  Int32 Function(Pointer<Void>, Pointer<Void>,
                      IntPtr)>>('TfLiteTensorCopyFromBuffer')
          .asFunction();

  late final int Function(
          Pointer<Void> tensor, Pointer<Void> outputData, int outputDataSize)
      tfLiteTensorCopyToBuffer = _lib
          .lookup<
              NativeFunction<
                  Int32 Function(Pointer<Void>, Pointer<Void>,
                      IntPtr)>>('TfLiteTensorCopyToBuffer')
          .asFunction();

  // --- XNNPACK Delegate ---

  late final void Function(Pointer<Void> options, Pointer<Void> delegate)
      tfLiteInterpreterOptionsAddDelegate = _lib
          .lookup<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>>(
              'TfLiteInterpreterOptionsAddDelegate')
          .asFunction();

  late final Pointer<Void> Function(
          Pointer<TfLiteXNNPackDelegateOptions> options)
      tfLiteXNNPackDelegateCreate = _lib
          .lookup<
                  NativeFunction<
                      Pointer<Void> Function(
                          Pointer<TfLiteXNNPackDelegateOptions>)>>(
              'TfLiteXNNPackDelegateCreate')
          .asFunction();

  late final void Function(Pointer<Void> delegate) tfLiteXNNPackDelegateDelete =
      _lib
          .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
              'TfLiteXNNPackDelegateDelete')
          .asFunction();

  // --- Tensor Shape ---

  late final int Function(Pointer<Void> tensor) tfLiteTensorNumDims = _lib
      .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>(
          'TfLiteTensorNumDims')
      .asFunction();

  late final int Function(Pointer<Void> tensor, int dimIndex) tfLiteTensorDim =
      _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Void>, Int32)>>(
              'TfLiteTensorDim')
          .asFunction();
}
