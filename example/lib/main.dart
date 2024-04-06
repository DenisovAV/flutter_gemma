import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma_platform_interface.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Gemma.instance.init(maxTokens: 50);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _exampleAnswer = 'No answer yet';
  final _gemma = Gemma.instance;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String exampleAnswer;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      exampleAnswer =
          await _gemma.getResponse(prompt: 'Tell me something interesting.') ?? 'Model doesn''t work';
    } on PlatformException {
      exampleAnswer = 'Failed to get Gemma answer.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _exampleAnswer = exampleAnswer;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Gemma Plugin example app'),
        ),
        body: Center(
          child: Text('Tell me something interesting: \n $_exampleAnswer\n'),
        ),
      ),
    );
  }
}
