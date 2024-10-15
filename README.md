# Flutter Gemma

[Gemma](https://ai.google.dev/gemma) is a family of lightweight, state-of-the art open models built from the same research and technology used to create the Gemini models

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma.png" alt="gemma_github_cover">
</p>

Bring the power of Google's lightweight Gemma language models directly to your Flutter applications. With Flutter Gemma, you can seamlessly incorporate advanced AI capabilities into your iOS and Android apps, all without relying on external servers.

There is an example of using:

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma.gif" alt="gemma_github_gif">
</p>

## Features

- **Local Execution:** Run Gemma models directly on user devices for enhanced privacy and offline functionality.
- **Platform Support:** Compatible with both iOS and Android platforms.
- **Ease of Use:** Simple interface for integrating Gemma models into your Flutter projects.

## Installation

1.  Add `flutter_gemma` to your `pubspec.yaml`:

    ```yaml
    dependencies:
      flutter_gemma: latest_version
    ```

2.  Run `flutter pub get` to install.

## Setup

1. **Download Model:** Obtain a pre-trained Gemma model (recommended: 2b or 2b-it) [from Kaggle](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/)
  * Optionally, [fine-tune a model for your specific use case]( https://www.kaggle.com/code/juanmerinobermejo/llm-pr-fine-tuning-with-gemma-2b?scriptVersionId=169776634)
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

3. **Prepare Model:**

Place the model in the assets or upload it to a network drive, such as Firebase.

#### ATTENTION!! You do not need to load the model every time the application starts; it is stored in the system files and only needs to be done once. Please carefully review the example application. You should use loadAssetModel and loadNetworkModel methods only when you need to upload the model to device

## Usage
1.**Loading Models from assets (available only in debug mode):**

Dont forget to add your model to pubspec.yaml

  1) Loading from assets 
```dart
    await FlutterGemmaPlugin.instance.loadAssetModel(fullPath: 'model.bin');
```

  2) Loading froms assets with Progress Status 
```dart
    FlutterGemmaPlugin.instance.loadAssetModelWithProgress(fullPath: 'model.bin').listen(
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

1.**Loading Models from network:**

* For web usage, you will also need to enable CORS (Cross-Origin Resource Sharing) for your network resource. To enable CORS in Firebase, you can follow the guide in the Firebase documentation: [Setting up CORS](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)

  1) Loading from the network.
```dart
   await FlutterGemmaPlugin.instance.loadNetworkModel(url: 'https://example.com/model.bin');
```

  2) Loading froms the network with Progress Status
```dart
    FlutterGemmaPlugin.instance.loadNetworkModelWithProgress(url: 'https://example.com/model.bin').listen(
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

3.**Initialize:**

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemmaPlugin.instance.init(
    maxTokens: 512,  /// maxTokens is optional, by default the value is 1024
    temperature: 1.0,   /// temperature is optional, by default the value is 1.0
    topK: 1,   /// topK is optional, by default the value is 1
    randomSeed: 1,   /// randomSeed is optional, by default the value is 1
  );

  runApp(const MyApp());
}
```

4.**Generate response**

```dart
final flutterGemma = FlutterGemmaPlugin.instance;
String response = await flutterGemma.getResponse(prompt: 'Tell me something interesting');
print(response);
```

5.**Generate response as a stream**

```dart
final flutterGemma = FlutterGemmaPlugin.instance;
flutterGemma.getAsyncResponse(prompt: 'Tell me something interesting').listen((String? token) => print(token));
```

6.**Generate chat response** This method works properly only for instruction tuned models

```dart
final flutterGemma = FlutterGemmaPlugin.instance;
final messages = <Message>[];
messages.add(Message(text: 'Who are you?', isUser: true);
String response = await flutterGemma.getChatResponse(messages: messages);
print(response);
messages.add(Message(text: response));
messages.add(Message(text: 'Really?', isUser: true));
String response = await flutterGemma.getChatResponse(messages: messages);
print(response);
```

7.**Generate chat response as a stream** This method works properly only for instruction tuned models

```dart
final flutterGemma = FlutterGemmaPlugin.instance;
final messages = <Message>[];
messages.add(Message(text: 'Who are you?', isUser: true);
flutterGemma.getAsyncChatResponse(messages: messages).listen((String? token) => print(token));
```

The full and complete example you can find in `example` folder

**Important Considerations**

* Larger models (like 7b and 7b-it) may be too resource-intensive for on-device use.

**Coming Soon**

* LoRA (Low Rank Adaptation) support

