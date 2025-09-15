import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'image_processor.dart';

/// Handles proper image tokenization for multimodal AI models to prevent
/// "Prompt contained 0 image tokens but received 1 images" errors and
/// corruption that causes repeating text patterns.
class ImageTokenizer {
  /// Creates a properly structured message object for multimodal AI models
  /// that prevents tokenization errors and image corruption.
  static Map<String, dynamic> createImageMessage({
    required String text,
    required ProcessedImage processedImage,
    required String role,
  }) {
    try {
      debugPrint('ImageTokenizer: Creating structured image message...');
      
      // Validate inputs
      if (text.isEmpty) {
        throw ImageTokenizationException('Text content cannot be empty');
      }
      
      if (processedImage.base64String.isEmpty) {
        throw ImageTokenizationException('Processed image Base64 string cannot be empty');
      }
      
      // Create structured message following multimodal AI model requirements
      final message = {
        'role': role,
        'content': [
          {
            'type': 'text',
            'text': text,
          },
          {
            'type': 'image',
            'image_data': {
              'data': processedImage.base64String,
              'format': processedImage.format,
            },
          },
        ],
      };
      
      debugPrint('ImageTokenizer: Structured message created with '
          '${(message['content'] as List).length} content items');
      
      return message;
    } catch (e) {
      debugPrint('ImageTokenizer: Error creating image message - $e');
      throw ImageTokenizationException('Failed to create image message: $e');
    }
  }
  
  /// Creates a properly formatted prompt for models that expect
  /// specific image token patterns.
  static String createImagePrompt({
    required String text,
    required ProcessedImage processedImage,
    required ModelType modelType,
  }) {
    try {
      debugPrint('ImageTokenizer: Creating image prompt for $modelType...');
      
      switch (modelType) {
        case ModelType.gemmaIt:
          return _createGemmaImagePrompt(text, processedImage);
        case ModelType.deepSeek:
          return _createDeepSeekImagePrompt(text, processedImage);
        case ModelType.general:
          return _createGeneralImagePrompt(text, processedImage);
      }
    } catch (e) {
      debugPrint('ImageTokenizer: Error creating image prompt - $e');
      throw ImageTokenizationException('Failed to create image prompt: $e');
    }
  }
  
  /// Creates Gemma-specific image prompt format
  static String _createGemmaImagePrompt(String text, ProcessedImage processedImage) {
    // Gemma models expect specific formatting to avoid tokenization errors
    final prompt = StringBuffer();
    
    // Add text content with proper formatting
    prompt.write('<start_of_turn>user\n');
    prompt.write(text);
    prompt.write('\n');
    
    // Add image token in Gemma-compatible format
    // This prevents the "0 image tokens but received 1 images" error
    prompt.write('<image>');
    prompt.write(processedImage.base64String);
    prompt.write('</image>');
    prompt.write('\n<start_of_turn>model\n');
    
    final result = prompt.toString();
    debugPrint('ImageTokenizer: Created Gemma prompt (${result.length} chars)');
    return result;
  }
  
  /// Creates DeepSeek-specific image prompt format
  static String _createDeepSeekImagePrompt(String text, ProcessedImage processedImage) {
    // DeepSeek models use different tokenization patterns
    final prompt = StringBuffer();
    
    prompt.write('<｜begin▁of▁sentence｜><｜User｜>');
    prompt.write(text);
    prompt.write('<｜image｜>');
    prompt.write(processedImage.base64String);
    prompt.write('<｜/image｜><｜Assistant｜>');
    
    final result = prompt.toString();
    debugPrint('ImageTokenizer: Created DeepSeek prompt (${result.length} chars)');
    return result;
  }
  
  /// Creates general-purpose image prompt format
  static String _createGeneralImagePrompt(String text, ProcessedImage processedImage) {
    // General format that works with most vision-language models
    final prompt = StringBuffer();
    
    prompt.write('<start_of_turn>user\n');
    prompt.write(text);
    prompt.write('\n[IMAGE]');
    prompt.write(processedImage.base64String);
    prompt.write('[/IMAGE]\n');
    prompt.write('<start_of_turn>model\n');
    
    final result = prompt.toString();
    debugPrint('ImageTokenizer: Created general prompt (${result.length} chars)');
    return result;
  }
  
  /// Validates that a message contains proper image tokens
  static bool validateImageTokens(String prompt, int expectedImageCount) {
    try {
      debugPrint('ImageTokenizer: Validating image tokens - expected: $expectedImageCount');
      
      // Count image tokens using various patterns
      int imageTokenCount = 0;
      
      // Check for common image token patterns
      final patterns = [
        RegExp(r'<image>.*?</image>', dotAll: true),
        RegExp(r'<｜image｜>.*?</｜image｜>', dotAll: true),
        RegExp(r'\[IMAGE\].*\[/IMAGE\]', dotAll: true),
        RegExp(r'image_data', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final matches = pattern.allMatches(prompt);
        imageTokenCount += matches.length;
      }
      
      // Also check for Base64 image data patterns
      final base64Pattern = RegExp(r'[A-Za-z0-9+/]{100,}={0,2}');
      final base64Matches = base64Pattern.allMatches(prompt);
      if (base64Matches.isNotEmpty) {
        // Estimate that large Base64 strings are likely images
        imageTokenCount += base64Matches.length;
      }
      
      debugPrint('ImageTokenizer: Found $imageTokenCount image tokens in prompt');
      
      return imageTokenCount >= expectedImageCount;
    } catch (e) {
      debugPrint('ImageTokenizer: Error validating image tokens - $e');
      return false;
    }
  }
  
  /// Detects potential image corruption patterns in model responses
  static bool detectCorruptionPatterns(String response) {
    try {
      if (response.isEmpty) return false;
      
      // Patterns that indicate image corruption
      final corruptionPatterns = [
        RegExp(r'describe\.describe\.describe\.+'), // Infinite "describe" repetition
        RegExp(r'^[₹]{10,}'), // Rupee symbol repetition
        RegExp(r'\bph\b.*\bph\b.*\bph\b'), // Repeating "ph" pattern
        RegExp(r'^(.)\1{10,}'), // Any single character repeated 10+ times
        RegExp(r'\b\w+\.\w+\.\w+\.+'), // Word repetition with dots
        RegExp(r'\b[a-zA-Z]{1,2}\s+[a-zA-Z]{1,2}\s+[a-zA-Z]{1,2}\b'), // Short letter sequences as words
      ];
      
      for (final pattern in corruptionPatterns) {
        if (pattern.hasMatch(response)) {
          debugPrint('ImageTokenizer: Detected corruption pattern - ${pattern.pattern}');
          return true;
        }
      }
      
      // Check for excessive repetition of short sequences
      final words = response.split(RegExp(r'\s+'));
      if (words.length > 10) {
        final wordCounts = <String, int>{};
        for (final word in words) {
          if (word.length <= 3) { // Focus on short words that might be corrupted data
            wordCounts[word] = (wordCounts[word] ?? 0) + 1;
          }
        }
        
        // If any short word appears too frequently, it might be corruption
        for (final entry in wordCounts.entries) {
          if (entry.value > words.length * 0.3) { // More than 30% of words
            debugPrint('ImageTokenizer: Detected excessive repetition of "${entry.key}" (${entry.value} times)');
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('ImageTokenizer: Error detecting corruption patterns - $e');
      return false;
    }
  }
  
  /// Creates a safe fallback prompt when image processing fails
  static String createFallbackPrompt(String text, {String? errorMessage}) {
    debugPrint('ImageTokenizer: Creating fallback prompt due to: $errorMessage');
    
    final prompt = StringBuffer();
    prompt.write('User provided an image but it could not be processed properly. ');
    if (errorMessage != null) {
      prompt.write('Error: $errorMessage. ');
    }
    prompt.write('Please respond to the following text only: ');
    prompt.write(text);
    
    return prompt.toString();
  }
}

/// Model types that require different tokenization approaches
enum ModelType {
  gemmaIt,
  deepSeek,
  general,
}

/// Exception thrown when image tokenization fails
class ImageTokenizationException implements Exception {
  final String message;
  final Exception? cause;
  
  const ImageTokenizationException(this.message, [this.cause]);
  
  @override
  String toString() => 'ImageTokenizationException: $message';
}
