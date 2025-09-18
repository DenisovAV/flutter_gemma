import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'image_processor.dart';
import 'image_tokenizer.dart' as tokenizer;
import 'vision_encoder_validator.dart';
import 'image_error_handler.dart';
import 'message.dart';
import 'model.dart';

/// Main integration class for handling multimodal image processing in Flutter Gemma
/// to prevent AI image corruption and repeating text pattern issues.
class MultimodalImageHandler {
  /// Processes and validates an image for use with AI models
  static Future<MultimodalImageResult> processImageForAI({
    required Uint8List imageBytes,
    required ModelType modelType,
    String? originalFormat,
    bool enableValidation = true,
    bool enableProcessing = true,
  }) async {
    try {
      debugPrint('MultimodalImageHandler: Starting image processing for $modelType...');
      
      // Step 1: Validate image for vision encoder compatibility
      ProcessedImage? processedImage;
      if (enableProcessing) {
        processedImage = await _processImageWithValidation(imageBytes, modelType, originalFormat);
      } else {
        // Just validate format if processing is disabled
        final format = ImageProcessor.detectFormat(imageBytes);
        processedImage = ProcessedImage(
          originalBytes: imageBytes,
          processedBytes: imageBytes,
          base64String: '', // Will be set later if needed
          width: 0,
          height: 0,
          format: format,
          originalFormat: originalFormat ?? format,
        );
      }
      
      // Step 2: Validate for specific vision encoder
      if (enableValidation) {
        final encoderType = _getVisionEncoderType(modelType);
        final validationResult = VisionEncoderValidator.validateForEncoder(
          imageBytes: processedImage.processedBytes,
          encoderType: encoderType,
          originalFormat: processedImage.originalFormat,
        );
        
        if (!validationResult.isValid) {
          throw VisionEncoderValidationException(
            'Image validation failed: ${validationResult.message}'
          );
        }
      }
      
      debugPrint('MultimodalImageHandler: Image processing completed successfully');
      
      return MultimodalImageResult(
        success: true,
        processedImage: processedImage,
        modelType: modelType,
        validationPassed: enableValidation,
      );
    } catch (e, stackTrace) {
      debugPrint('MultimodalImageHandler: Image processing failed - $e');
      
      // Handle the error and provide recovery suggestions
      final errorResult = ImageErrorHandler.handleImageProcessingError(
        e,
        stackTrace,
        imageBytes: imageBytes,
        context: 'MultimodalImageHandler.processImageForAI',
      );
      
      return MultimodalImageResult(
        success: false,
        error: errorResult,
        modelType: modelType,
        validationPassed: false,
      );
    }
  }
  
  /// Processes image with comprehensive validation
  static Future<ProcessedImage> _processImageWithValidation(
    Uint8List imageBytes,
    ModelType modelType,
    String? originalFormat,
  ) async {
    // Process the image using ImageProcessor
    final processedImage = await ImageProcessor.processImage(
      imageBytes,
      originalFormat: originalFormat,
    );
    
    debugPrint('MultimodalImageHandler: Image processed - ${processedImage.width}x${processedImage.height}, '
        'Format: ${processedImage.format}, Base64 Length: ${processedImage.base64Length}');
    
    return processedImage;
  }
  
  /// Creates a properly formatted message for multimodal AI models
  static Message createMultimodalMessage({
    required String text,
    required ProcessedImage processedImage,
    required ModelType modelType,
    bool isUser = true,
  }) {
    try {
      debugPrint('MultimodalImageHandler: Creating multimodal message for $modelType...');
      
      // Validate inputs
      if (text.isEmpty) {
        throw ArgumentError('Text content cannot be empty');
      }
      
      if (processedImage.base64String.isEmpty) {
        throw ArgumentError('Processed image Base64 string cannot be empty');
      }
      
      // Create the message with proper image handling
      return Message.withImage(
        text: text,
        imageBytes: processedImage.processedBytes,
        isUser: isUser,
      );
    } catch (e, stackTrace) {
      debugPrint('MultimodalImageHandler: Failed to create multimodal message - $e');
      
      // Try to create a fallback text-only message
      final fallbackText = '${text}\n[Note: Image could not be processed properly]';
      return Message.text(text: fallbackText, isUser: isUser);
    }
  }
  
  /// Creates a properly tokenized prompt for the AI model
  static String createTokenizedPrompt({
    required String text,
    required ProcessedImage processedImage,
    required ModelType modelType,
  }) {
    try {
      debugPrint('MultimodalImageHandler: Creating tokenized prompt for $modelType...');
      
      // Use ImageTokenizer to create properly formatted prompt
      final prompt = tokenizer.ImageTokenizer.createImagePrompt(
        text: text,
        processedImage: processedImage,
        modelType: _convertToTokenizerModelType(modelType),
      );
      
      // Validate the prompt contains proper image tokens
      final hasValidTokens = tokenizer.ImageTokenizer.validateImageTokens(prompt, 1);
      if (!hasValidTokens) {
        debugPrint('MultimodalImageHandler: Warning - Prompt may have tokenization issues');
      }
      
      debugPrint('MultimodalImageHandler: Tokenized prompt created (${prompt.length} chars)');
      
      return prompt;
    } catch (e, stackTrace) {
      debugPrint('MultimodalImageHandler: Tokenization failed - $e');
      
      // Handle tokenization error
      final errorResult = ImageErrorHandler.handleTokenizationError(
        e,
        stackTrace,
        modelType: _convertToTokenizerModelType(modelType),
        prompt: text,
        expectedImageCount: 1,
      );
      
      // Return fallback prompt
      return tokenizer.ImageTokenizer.createFallbackPrompt(text, errorMessage: errorResult.message);
    }
  }
  
  /// Validates and handles model responses for corruption patterns
  static ResponseValidationResult validateModelResponse(
    String response, {
    required String originalPrompt,
    required ProcessedImage? processedImage,
  }) {
    try {
      debugPrint('MultimodalImageHandler: Validating model response...');
      
      // Detect corruption patterns
      final corruptionResult = ImageErrorHandler.detectResponseCorruption(response);
      
      if (corruptionResult.isCorrupted) {
        debugPrint('MultimodalImageHandler: Corruption detected with ${corruptionResult.confidence.toStringAsFixed(2)} confidence');
        
        // Log detailed analysis
        debugPrint('Corruption Analysis: ${corruptionResult.analysis}');
        debugPrint('Suggested Action: ${corruptionResult.suggestedAction}');
        
        return ResponseValidationResult(
          isValid: false,
          isCorrupted: true,
          confidence: corruptionResult.confidence,
          analysis: corruptionResult.analysis,
          suggestedAction: _convertToResponseAction(corruptionResult.suggestedAction),
          originalResponse: response,
        );
      }
      
      debugPrint('MultimodalImageHandler: Response validation passed');
      
      return ResponseValidationResult(
        isValid: false,
        isCorrupted: true,
        confidence: 0.8, // High confidence in error case
        analysis: {'status': 'validation_error'},
        suggestedAction: ResponseAction.reprocessImage,
        originalResponse: response,
      );
    } catch (e, stackTrace) {
      debugPrint('MultimodalImageHandler: Response validation failed - $e');
      
      return ResponseValidationResult(
        isValid: false,
        isCorrupted: true,
        confidence: 0.8, // High confidence in error case
        analysis: {'error': 'Validation failed: $e'},
        suggestedAction: ResponseAction.reprocessImage,
        originalResponse: response,
      );
    }
  }
  
  /// Gets the appropriate vision encoder type for the model
  static VisionEncoderType _getVisionEncoderType(ModelType modelType) {
    switch (modelType) {
      case ModelType.gemmaIt:
        return VisionEncoderType.gemma3SigLIP;
      case ModelType.deepSeek:
      case ModelType.general:
        return VisionEncoderType.general;
    }
  }
  
  /// Converts ModelType to ImageTokenizer ModelType
  static tokenizer.ModelType _convertToTokenizerModelType(ModelType modelType) {
    switch (modelType) {
      case ModelType.gemmaIt:
        return tokenizer.ModelType.gemmaIt;
      case ModelType.deepSeek:
        return tokenizer.ModelType.deepSeek;
      case ModelType.general:
        return tokenizer.ModelType.general;
    }
  }
  
  /// Converts corruption action to response action
  static ResponseAction _convertToResponseAction(CorruptionAction action) {
    switch (action) {
      case CorruptionAction.none:
        return ResponseAction.none;
      case CorruptionAction.monitorResponse:
        return ResponseAction.monitorResponse;
      case CorruptionAction.validateImage:
        return ResponseAction.validateImage;
      case CorruptionAction.reprocessImage:
        return ResponseAction.reprocessImage;
    }
  }
  
  /// Utility method to safely extract Base64 from various formats
  static String? extractBase64FromPrompt(String prompt) {
    try {
      // Look for common Base64 patterns in prompts
      final base64Pattern = RegExp(r'[A-Za-z0-9+/]{100,}={0,2}');
      final matches = base64Pattern.allMatches(prompt);
      
      if (matches.isNotEmpty) {
        // Return the longest match (most likely to be the image)
        String? longestMatch;
        int maxLength = 0;
        
        for (final match in matches) {
          if (match.group(0)!.length > maxLength) {
            maxLength = match.group(0)!.length;
            longestMatch = match.group(0);
          }
        }
        
        return longestMatch;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error extracting Base64 from prompt: $e');
      return null;
    }
  }
  
  /// Creates a diagnostic report for troubleshooting
  static DiagnosticReport createDiagnosticReport({
    required Uint8List imageBytes,
    required ModelType modelType,
    String? processedBase64,
    String? prompt,
    String? response,
  }) {
    try {
      debugPrint('MultimodalImageHandler: Creating diagnostic report...');
      
      final format = ImageProcessor.detectFormat(imageBytes);
      final sizeInKB = imageBytes.length / 1024;
      
      final validationResult = VisionEncoderValidator.validateForEncoder(
        imageBytes: imageBytes,
        encoderType: _getVisionEncoderType(modelType),
        originalFormat: format,
      );
      
      final report = DiagnosticReport(
        timestamp: DateTime.now(),
        modelType: modelType,
        originalFormat: format,
        originalSizeKB: sizeInKB,
        validationResult: validationResult,
        processedBase64Length: processedBase64?.length ?? 0,
        promptLength: prompt?.length ?? 0,
        responseLength: response?.length ?? 0,
        hasProcessedImage: processedBase64 != null,
        hasPrompt: prompt != null,
        hasResponse: response != null,
      );
      
      debugPrint('MultimodalImageHandler: Diagnostic report created');
      return report;
    } catch (e) {
      debugPrint('MultimodalImageHandler: Diagnostic report failed - $e');
      rethrow;
    }
  }
}

/// Result of multimodal image processing
class MultimodalImageResult {
  final bool success;
  final ProcessedImage? processedImage;
  final ErrorHandlingResult? error;
  final ModelType modelType;
  final bool validationPassed;
  
  const MultimodalImageResult({
    required this.success,
    this.processedImage,
    this.error,
    required this.modelType,
    required this.validationPassed,
  });
  
  bool get hasImage => processedImage != null;
  bool get hasError => error != null;
}

/// Result of response validation
class ResponseValidationResult {
  final bool isValid;
  final bool isCorrupted;
  final double confidence;
  final Map<String, dynamic> analysis;
  final ResponseAction suggestedAction;
  final String originalResponse;
  
  const ResponseValidationResult({
    required this.isValid,
    required this.isCorrupted,
    required this.confidence,
    required this.analysis,
    required this.suggestedAction,
    required this.originalResponse,
  });
  
  bool get shouldReprocess => suggestedAction == ResponseAction.reprocessImage;
  bool get shouldValidate => suggestedAction == ResponseAction.validateImage;
}

/// Actions to take for corrupted responses
enum ResponseAction {
  none,
  monitorResponse,
  validateImage,
  reprocessImage,
}

/// Diagnostic information for troubleshooting
class DiagnosticReport {
  final DateTime timestamp;
  final ModelType modelType;
  final String originalFormat;
  final double originalSizeKB;
  final ValidationResult validationResult;
  final int processedBase64Length;
  final int promptLength;
  final int responseLength;
  final bool hasProcessedImage;
  final bool hasPrompt;
  final bool hasResponse;
  
  const DiagnosticReport({
    required this.timestamp,
    required this.modelType,
    required this.originalFormat,
    required this.originalSizeKB,
    required this.validationResult,
    required this.processedBase64Length,
    required this.promptLength,
    required this.responseLength,
    required this.hasProcessedImage,
    required this.hasPrompt,
    required this.hasResponse,
  });
  
  @override
  String toString() {
    return 'DiagnosticReport(${timestamp.toIso8601String()}, '
        'Model: ${modelType.name}, Format: $originalFormat, '
        'Size: ${originalSizeKB.toStringAsFixed(1)}KB, '
        'Validation: ${validationResult.isValid}, '
        'Base64: $processedBase64Length chars)';
  }
}
