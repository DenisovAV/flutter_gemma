import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma_example/chat_screen.dart';
import 'package:flutter_gemma_example/models/model.dart';

class ModelSelectionScreen extends StatelessWidget {
  const ModelSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b2351),
      appBar: AppBar(
        title: const Text('Select a Model'),
        backgroundColor: const Color(0xFF0b2351),
      ),
      body: ListView.builder(
        itemCount: Model.values.length,
        itemBuilder: (context, index) {
          var modelCanRun =
              !(Model.values[index].preferredBackend == PreferredBackend.cpu &&
                  kIsWeb);
          return ListTile(
            title: Text(Model.values[index].name),
            enabled: modelCanRun,
            onTap: () {
              if (modelCanRun) {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) {
                      // TODO: Open browser to authenticate and get huggingface token if not authenticated.
                      // TODO: Open browser to license agreement if not accepted.
                      // TODO: Open model download screen if model is not downloaded.
                      return ChatScreen(model: Model.values[index]);
                    },
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}
