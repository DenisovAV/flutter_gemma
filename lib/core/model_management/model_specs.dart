/// Model specification value types — `dart:io`-free, shared across all
/// platforms (mobile, desktop, web).
///
/// These types used to be `part of` `flutter_gemma_mobile.dart`, which pulled
/// `dart:io` (and `path_provider`) into the public import graph and broke
/// dart2wasm compatibility (pub.dev "Platform support" WASM check). They are
/// extracted here as a standalone, platform-neutral library so the public API
/// surface and the platform interface can depend on the specs without dragging
/// in the mobile implementation's `dart:io`.
library;

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/model_file_manager_interface.dart'
    show ModelReplacePolicy;

part 'types/model_spec.dart';
part 'types/inference_model_spec.dart';
part 'types/embedding_model_spec.dart';
part 'types/storage_info.dart';
part 'exceptions/model_exceptions.dart';
