# Flutter Gemma

**The plugin supports not only Gemma, but also other models. Here’s the full list of supported models:**

[Gemma 2B](https://huggingface.co/google/gemma-2b-it) & [Gemma 7B](https://huggingface.co/google/gemma-7b-it), [Gemma-2 2B](https://huggingface.co/google/gemma-2-2b-it), [Gemma 3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT), Phi-2, Phi-3 , [Phi-4](https://huggingface.co/litert-community/Phi-4-mini-instruct), [DeepSeek](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B), Falcon-RW-1B, StableLM-3B.

Note: Currently, the flutter_gemma plugin supports Gemma 3 and DeepSeek only for **Android** and **Web** platforms. Support for iOS will be added in a future update. Gemma, Gemma 2 and others are supported for all platforms

[Gemma](https://ai.google.dev/gemma) is a family of lightweight, state-of-the art open models built from the same research and technology used to create the Gemini models

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma3.png" alt="gemma_github_cover">
</p>

Bring the power of Google's lightweight Gemma language models directly to your Flutter applications. With Flutter Gemma, you can seamlessly incorporate advanced AI capabilities into your iOS and Android apps, all without relying on external servers.

There is an example of using:

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma.gif" alt="gemma_github_gif">
</p>

## Features

- **Local Execution:** Run Gemma models directly on user devices for enhanced privacy and offline functionality.
- **Platform Support:** Compatible with both iOS and Android platforms.
- **LoRA Support:** Efficient fine-tuning and integration of LoRA (Low-Rank Adaptation) weights for tailored AI behavior.
- **Ease of Use:** Simple interface for integrating Gemma models into your Flutter projects.


## Installation

1.  Add `flutter_gemma` to your `pubspec.yaml`:

    ```yaml
    dependencies:
      flutter_gemma: latest_version
    ```

2.  Run `flutter pub get` to install.

## Setup

1. **Download Model and optionally LoRA Weights:** Obtain a pre-trained Gemma model (recommended: 2b or 2b-it) [from Kaggle](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/)
  * Optionally, [fine-tune a model for your specific use case]( https://www.kaggle.com/code/juanmerinobermejo/llm-pr-fine-tuning-with-gemma-2b?scriptVersionId=169776634)
  * If you have LoRA weights, you can use them to customize the model's behavior without retraining the entire model.
  * [There is an article that described all approaches](https://medium.com/@denisov.shureg/fine-tuning-gemma-with-lora-for-on-device-inference-android-ios-web-with-separate-lora-weights-f05d1db30d86)
2. **Platfrom specific setup:**

**iOS**
* Enable file sharing in `info.plist`:
```plist
<key>UIFileSharingEnabled</key>
<true/>
```
* Change the linking type of pods to static, replace `use_frameworks!` in Podfile with `use_frameworks! :linkage => :static`

**Android**

* If you want to use a GPU to work with the model, you need to add OpenGL support in the manifest.xml. If you plan to use only the CPU, you can skip this step.

Add to 'AndroidManifest.xml' above tag `</application>`

```AndroidManifest.xml
 <uses-native-library
     android:name="libOpenCL.so"
     android:required="false"/>
 <uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
 <uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

**Web**

* Web currently works only GPU backend models, CPU backend models are not suported by Mediapipe yet

* Add dependencies to `index.html` file in web folder
```html
  <script type="module">
  import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai';
  window.FilesetResolver = FilesetResolver;
  window.LlmInference = LlmInference;
  </script>
```

## Usage

The new API splits functionality into two parts:

* **ModelFileManager**: Manages model and LoRA weights file handling.
* **InferenceModel**: Handles model initialization and response generation.

The updated API splits the functionality into two main parts:

* Access the plugin via:
    
```dart
final gemma = FlutterGemmaPlugin.instance;
```

* Managing Model Files with ModelFileManager

```dart
final modelManager = gemma.modelManager;
```


Place the model in the assets or upload it to a network drive, such as Firebase.
#### ATTENTION!! You do not need to load the model every time the application starts; it is stored in the system files and only needs to be done once. Please carefully review the example application. You should use loadAssetModel and loadNetworkModel methods only when you need to upload the model to device

## Usage
1.**Loading Models from assets (available only in debug mode):**

Dont forget to add your model to pubspec.yaml

  1) Loading from assets (loraUrl is optional)
```dart
    await modelManager.installModelFromAsset('model.bin', loraPath: 'lora_weights.bin');
```

  2) Loading froms assets with Progress Status (loraUrl is optional)
```dart
    modelManager.installModelFromAssetWithProgress('model.bin', loraPath: 'lora_weights.bin').listen(
    (progress) {
      print('Loading progress: $progress%');
    },
    onDone: () {
      print('Model loading complete.');
    },
    onError: (error) {
      print('Error loading model: $error');
    },
  );
```

2.**Loading Models from network:**

* For web usage, you will also need to enable CORS (Cross-Origin Resource Sharing) for your network resource. To enable CORS in Firebase, you can follow the guide in the Firebase documentation: [Setting up CORS](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)

  1) Loading from the network (loraUrl is optional).
```dart
   await modelManager.downloadModelFromNetwork('https://example.com/model.bin', loraUrl: 'https://example.com/lora_weights.bin');
```

  2) Loading froms the network with Progress Status (loraUrl is optional)
```dart
    modelManager.downloadModelFromNetworkWithProgress('https://example.com/model.bin', loraUrl: 'https://example.com/lora_weights.bin').listen(
    (progress) {
      print('Loading progress: $progress%');
    },
    onDone: () {
      print('Model loading complete.');
    },
    onError: (error) {
      print('Error loading model: $error');
    },
);
```

3. **Loading LoRA Weights**

1) Loading LoRA weight from the network.
```dart
await modelManager.downloadLoraWeightsFromNetwork('https://example.com/lora_weights.bin');
```

2) Loading LoRA weight from assets.
```dart
await modelManager.installLoraWeightsFromAsset('lora_weights.bin');
```

4. **Model Management**
You can set model and weights paths manually
```dart
await modelManager.setModelPath('model.bin');
await modelManager.setLoraWeightsPath('lora_weights.bin');
```

You can delete the model and weights from the device. Deleting the model or LoRA weights will automatically close and clean up the inference. This ensures that there are no lingering resources or memory leaks when switching models or updating files.
```dart
await modelManager.deleteModel();
await modelManager.deleteLoraWeights();
```

5.**Initialize:**

Before performing any inference, you need to create a model instance. This ensures that your application is ready to handle requests efficiently.

```dart
final inferenceModel = await FlutterGemmaPlugin.instance.createModel(
modelType: ModelType.gemmaIt, // Required, model type to create
preferedBackend: BackendType.gpu, // Optional, backendType, default is BackendType.gpu
maxTokens: 512, // Optional, default is 1024
);
```

6.**Using Sessions for Single Inferences:**

If you need to generate individual responses without maintaining a conversation history, use sessions. Sessions allow precise control over inference and must be properly closed to avoid memory leaks.

1) Synchronous Response Generation

```dart
final session = await inferenceModel.createSession(
  temperature: 1.0, // Optional, default is 0.8
  randomSeed: 1, // Optional, default is 1
  topK: 1, // Optional, default is 1
);

await session.addQueryChunk(Message(text: 'Tell me something interesting'));
String response = await session.getResponse();
print(response);

await session.close(); // Always close the session when done
```
2) Asynchronous Response Generation

```dart
final session = await inferenceModel.createSession();
await session.addQueryChunk(Message(text: 'Tell me something interesting'));

session.getResponseAsync().listen((String token) {
print(token);
}, onDone: () {
print('Stream closed');
}, onError: (error) {
print('Error: $error');
});

await session.close();  // Always close the session when done
```

7.**Chat Scenario with Automatic Session Management**

For chat-based applications, you can create a chat instance. Unlike sessions, the chat instance manages the conversation context and refreshes sessions when necessary.

```dart
final chat = await inferenceModel.createChat(
  temperature: 0.8, // Controls response randomness
  randomSeed: 1, // Ensures reproducibility
  topK: 1, // Limits vocabulary scope
);
```

1) Synchronous Chat

```dart
await chat.addQueryChunk(Message(text: 'User: Hello, who are you?'));
String response = await chat.generateChatResponse();
print(response);

await chat.addQueryChunk(Message(text: 'User: Are you sure?'));
String response2 = await chat.generateChatResponse();
print(response2);
```

2) Asynchronous Chat (Streaming)

```dart
await chat.addQueryChunk(Message(text: 'User: Hello, who are you?'));

chat.generateChatResponseAsync().listen((String token) {
  print(token);
}, onDone: () {
  print('Chat stream closed');
}, onError: (error) {
  print('Chat error: $error');
});

await chat.addQueryChunk(Message(text: 'User: Are you sure?'));
chat.generateChatResponseAsync().listen((String token) {
  print(token);
}, onDone: () {
  print('Chat stream closed');
}, onError: (error) {
  print('Chat error: $error');
});
```

8.**Checking Token Usage**
You can check the token size of a prompt before inference. The accumulated context should not exceed maxTokens to ensure smooth operation.

```dart
int tokenCount = await session.sizeInTokens('Your prompt text here');
print('Prompt size in tokens: $tokenCount');
```

9.**Closing the Model** 

When you no longer need to perform any further inferences, call the close method to release resources:

```dart 
await inferenceModel.close();
```

If you need to use the inference again later, remember to call `createModel` again before generating responses.


The full and complete example you can find in `example` folder

**Important Considerations**

* Model Size: Larger models (such as 7b and 7b-it) might be too resource-intensive for on-device inference.
* LoRA Weights: They provide efficient customization without the need for full model retraining.
* Development vs. Production: For production apps, do not embed the model or LoRA weights within your assets. Instead, load them once and store them securely on the device or via a network drive.
* Web Models: Currently, Web support is available only for GPU backend models.

**Upcoming Features**

In the next version, expect support for multimodality with Gemma 3, enabling text, image, and potentially other input types for even more advanced AI-powered applications.

