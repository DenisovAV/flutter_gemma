import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma_example/chat_screen.dart';
import 'package:flutter_gemma_example/model_download_screen.dart';
import 'package:flutter_gemma_example/models/model.dart';

class ModelSelectionScreen extends StatelessWidget {
  const ModelSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final models = Model.values.where((model) {
      if (model.localModel) {
        return kIsWeb;
      }
      if (!kIsWeb) return true;
      return model.preferredBackend == PreferredBackend.gpu && !model.needsAuth;
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0b2351),
      appBar: AppBar(
        title: const Text('Select a Model'),
        backgroundColor: const Color(0xFF0b2351),
      ),
      body: ListView.builder(
        itemCount: models.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(models[index].displayName),
            onTap: () {
              if (!kIsWeb) {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => ModelDownloadScreen(
                      model: models[index],
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => ChatScreen(
                      model: models[index],
                    ),
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
