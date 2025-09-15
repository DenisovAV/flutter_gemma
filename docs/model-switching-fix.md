# Model Switching Fix - Root Cause Analysis and Solution

## Problem Summary

The error logs showed a critical issue where the Flutter Gemma app was trying to open a model file that didn't exist:

```
Failed to initialize LlmInference: Failed to initialize engine: %sINTERNAL: CalculatorGraph::Run() failed: 
Calculator::Open() for node "odml.infra.LiteRTResourceCalculator" failed: RET_CHECK failure 
(third_party/odml/litert_lm/runtime/util/scoped_file_posix.cc:27) fd >= 0 (-1 vs. 0) open() failed: 
/data/user/0/dev.flutterberlin.flutter_gemma_example/app_flutter/gemma-3n-E2B-it-int4.task
```

**Key Issue**: The app was trying to open `gemma-3n-E2B-it-int4.task` but had actually downloaded `gemma-3n-E4B-it-int4.task`.

## Root Cause Analysis

### 1. **Stale Model Reference Cache**
The `MobileModelManager` caches the model filename in SharedPreferences (`_prefsModelKey`) but doesn't update it when switching between different models.

### 2. **Model Switching Scenario**
- User initially selected `gemma3n_2B` (filename: `gemma-3n-E2B-it-int4.task`)
- SharedPreferences cached this filename
- User switched to `gemma3n_4B` (filename: `gemma-3n-E4B-it-int4.task`)
- The new model downloaded correctly as `gemma-3n-E4B-it-int4.task`
- But the cached filename in SharedPreferences remained `gemma-3n-E2B-it-int4.task`
- Model initialization tried to open the old cached filename, causing the failure

### 3. **Phone Restart Complication**
After the phone restart, the app tried to reinitialize with the cached (incorrect) filename, leading to the persistent "Initializing model" loading screen.

## Solution Implementation

### 1. **Enhanced Model Manager Interface**
Added two new methods to `ModelFileManager`:
```dart
/// Forces update of the cached model filename - useful when switching between different models
Future<void> forceUpdateModelFilename(String filename);

/// Clears all model cache and resets state - useful for model switching
Future<void> clearModelCache();
```

### 2. **Fixed setModelPath Method**
Updated `MobileModelManager.setModelPath()` to properly update the cached filename:
```dart
@override
Future<void> setModelPath(String path, {String? loraPath}) async {
  await Future.wait([
    _loadModelIfNeeded(() async {
      _userSetModelPath = path;
      // Update the cached filename when setting a new path
      final fileName = Uri.parse(path).pathSegments.last;
      _modelFileName = fileName;
      final prefs = await _prefs;
      await prefs.setString(_prefsModelKey, fileName);
      return;
    }),
    // ... rest of method
  ]);
}
```

### 3. **Enhanced Chat Screen Initialization**
Updated `ChatScreen._initializeModel()` to properly handle model switching:
```dart
Future<void> _initializeModel() async {
  try {
    // Clear any cached model references when switching models
    await _gemma.modelManager.clearModelCache();
    
    if (!await _gemma.modelManager.isModelInstalled) {
      final path = kIsWeb ? widget.model.url : '${(await getApplicationDocumentsDirectory()).path}/${widget.model.filename}';
      await _gemma.modelManager.setModelPath(path);
    } else {
      // Force update the cached filename to match the current model
      await _gemma.modelManager.forceUpdateModelFilename(widget.model.filename);
    }
    
    // ... rest of initialization with proper error handling
  } catch (e) {
    setState(() {
      _error = 'Failed to initialize model: ${e.toString()}';
      _isModelInitialized = false;
    });
    rethrow;
  }
}
```

### 4. **Web Platform Compatibility**
Added stub implementations for `WebModelManager` since web doesn't use file caching:
```dart
@override
Future<void> forceUpdateModelFilename(String filename) {
  // For web, we don't cache filenames, so this is a no-op
  return Future.value();
}

@override
Future<void> clearModelCache() {
  // For web, we don't cache model state, so this is a no-op
  _loadCompleter = null;
  _path = null;
  _loraPath = null;
  return Future.value();
}
```

## Files Modified

1. **`lib/model_file_manager_interface.dart`** - Added new interface methods
2. **`lib/mobile/flutter_gemma_mobile_model_manager.dart`** - Fixed caching logic and added new methods
3. **`lib/web/flutter_gemma_web.dart`** - Added web platform implementations
4. **`example/lib/chat_screen.dart`** - Updated model initialization logic
5. **`test/model_switching_test.dart`** - Added test to verify the fix

## Testing

Created a test that verifies:
- Different model filenames are handled correctly
- The specific filename mismatch issue is resolved
- The new cache management methods work properly

Run the test with:
```bash
flutter test test/model_switching_test.dart
```

## Expected Behavior After Fix

1. **Model Switching**: When switching from `gemma3n_2B` to `gemma3n_4B`, the app will:
   - Clear the old cached filename
   - Update to the new correct filename
   - Successfully initialize the new model

2. **App Restart**: After phone restart, the app will:
   - Properly detect the current model
   - Use the correct filename for initialization
   - Avoid the "Initializing model" infinite loading screen

3. **Error Handling**: Better error messages and graceful failure handling during model initialization

## Secondary Issues Addressed

- **JobService warnings**: These are less critical and related to the background download system
- **Frame timing issues**: Flutter frame clamping warnings that don't affect functionality

The primary issue of model switching and stale filename caching has been resolved.
