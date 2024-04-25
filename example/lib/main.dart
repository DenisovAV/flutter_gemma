import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterGemmaPlugin.instance.init(
    maxTokens: 512,
    temperature: 1.0,
    topK: 1,
    randomSeed: 1,
  );
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Gemma Example',
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const SafeArea(child: ChatScreen()),
    );
  }
}
