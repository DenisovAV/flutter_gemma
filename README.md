# Flutter Gemma

[Gemma](https://ai.google.dev/gemma) is a family of lightweight, state-of-the art open models built from the same research and technology used to create the Gemini models

![gemini_github_cover](https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma.png)

Bring the power of Google's lightweight Gemma language models directly to your Flutter applications. With Flutter Gemma, you can seamlessly incorporate advanced AI capabilities into your iOS and Android apps, all without relying on external servers.

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
2. **Rename Model:** Rename the downloaded file to `model.bin`.
3. **Integrate Model into Your App:**

**iOS**
* Enable file sharing in `info.plist`:
```plist
<key>UIFileSharingEnabled</key>
<true/>
```
* Transfer `model.bin` to your device
  1. Connect your iPhone
  2. Open Finder, your iPhone should appear in the Finder's sidebar under "Locations." Click on it.
  3. Access Files. In the button bar, click on "Files" to see apps that can transfer files between your iPhone and Mac.
  4. Drag and Drop or Add Files. You can drag `model.bin` directly to an app under the "Files" section to transfer them. Alternatively, click the "Add" button to browse and select `model.bin` to upload.

**Android**

* Transfer `model.bin` to your device (for testing purposes only, uploading by network will be implemented in next versions)
  1. Install adb tool, if you didn't install it before
  2. Connect your Android device
  3. Copy `model.bin` to the output_path folder
  4. Push the content of the output_path folder to the Android device

```shell
 adb shell rm -r /data/local/tmp/llm/ # Remove any previously loaded models
 adb shell mkdir -p /data/local/tmp/llm/
 adb push output_path /data/local/tmp/llm/model.bin
 ```


## Usage

1. **Initialize:**

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Gemma.instance.init(maxTokens: 50);   /// maxTokens is optional, by default the value is 1024
  
  runApp(const MyApp());
}
```

2. **Generate response**

```dart
final gemma = Gemma.instance;
String response = await gemma.getResponse(prompt: 'Tell me something interesting');
print(response);
```

**Important Considerations**

* Currently, models must be manually transferred to devices for testing. Network download functionality will be included in future versions.
* Larger models (like 7b and 7b-it) may be too resource-intensive for on-device use.

**Coming Soon**

* Streaming responses for faster user interactions.
* Network-based model download for seamless updates.

