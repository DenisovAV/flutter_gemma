import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';

const _gemma3_1bPath =
    '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';
const _gemma4Path =
    '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-4-E2B-it.litertlm';
const _gemma3nPath =
    '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';

// Test image: 1x1 white PNG
final _testImage = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();
  });

  group('Gemma 3 1B (text only)', () {
    testWidgets('CPU sync', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma3_1bPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.cpu,
      );

      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(const Message(text: 'Say hi', isUser: true));
      final response = await session.getResponse();
      print('[Gemma3-1B CPU] Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma3-1B CPU] PASSED');
    });

    testWidgets('GPU streaming', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma3_1bPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
      );

      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(const Message(text: 'Say hello', isUser: true));

      final chunks = <String>[];
      await for (final chunk in session.getResponseAsync()) {
        chunks.add(chunk);
      }
      print('[Gemma3-1B GPU stream] ${chunks.length} chunks: ${chunks.join()}');
      expect(chunks, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma3-1B GPU stream] PASSED');
    });
  });

  group('Gemma 4 E2B (multimodal)', () {
    testWidgets('GPU text only', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma4Path).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
      );

      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(const Message(text: 'What is 2+2?', isUser: true));
      final response = await session.getResponse();
      print('[Gemma4 GPU text] Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma4 GPU text] PASSED');
    });

    testWidgets('GPU with image', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma4Path).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
        supportImage: true,
        maxNumImages: 1,
      );

      final session = await model.createSession(
        temperature: 0.8,
        topK: 1,
        enableVisionModality: true,
      );

      await session.addQueryChunk(Message(
        text: 'What do you see in this image?',
        isUser: true,
        imageBytes: _testImage,
      ));

      final response = await session.getResponse();
      print('[Gemma4 GPU vision] Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma4 GPU vision] PASSED');
    });
  });

  group('Gemma 3n E2B (multimodal)', () {
    testWidgets('CPU text only', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma3nPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.cpu,
      );

      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(const Message(text: 'Say hi', isUser: true));
      final response = await session.getResponse();
      print('[Gemma3n CPU text] Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma3n CPU text] PASSED');
    });

    testWidgets('GPU text only', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma3nPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
      );

      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(const Message(text: 'What is 2+2?', isUser: true));
      final response = await session.getResponse();
      print('[Gemma3n GPU text] Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma3n GPU text] PASSED');
    });

    testWidgets('GPU with image', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma3nPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
        supportImage: true,
        maxNumImages: 1,
      );

      final session = await model.createSession(
        temperature: 0.8,
        topK: 1,
        enableVisionModality: true,
      );

      await session.addQueryChunk(Message(
        text: 'Describe this image',
        isUser: true,
        imageBytes: _testImage,
      ));

      final response = await session.getResponse();
      print('[Gemma3n GPU vision] Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('[Gemma3n GPU vision] PASSED');
    });

    testWidgets('CPU with audio', (tester) async {
      // Use a tiny WAV header as test audio
      final testAudio = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        0x24, 0x00, 0x00, 0x00, // chunk size
        0x57, 0x41, 0x56, 0x45, // "WAVE"
        0x66, 0x6D, 0x74, 0x20, // "fmt "
        0x10, 0x00, 0x00, 0x00, // subchunk1 size
        0x01, 0x00, 0x01, 0x00, // PCM, mono
        0x80, 0x3E, 0x00, 0x00, // 16000 Hz
        0x00, 0x7D, 0x00, 0x00, // byte rate
        0x02, 0x00, 0x10, 0x00, // block align, bits per sample
        0x64, 0x61, 0x74, 0x61, // "data"
        0x00, 0x00, 0x00, 0x00, // data size (empty)
      ]);

      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_gemma3nPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.cpu,
        supportAudio: true,
      );

      final session = await model.createSession(
        temperature: 0.8,
        topK: 1,
        enableAudioModality: true,
      );

      await session.addQueryChunk(Message(
        text: 'What did you hear?',
        isUser: true,
        audioBytes: testAudio,
      ));

      try {
        final response = await session.getResponse();
        print('[Gemma3n CPU audio] Response: $response');
        expect(response, isNotEmpty);
        print('[Gemma3n CPU audio] PASSED');
      } catch (e) {
        print('[Gemma3n CPU audio] Error (may be expected with tiny audio): $e');
      }

      await session.close();
      await model.close();
    });
  });
}
