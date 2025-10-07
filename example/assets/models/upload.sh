#!/bin/bash
  PACKAGE="dev.flutterberlin.flutter_gemma_example"
  APP_DIR="/data/data/$PACKAGE/app_flutter"

  echo "📥 Загружаем файлы в /data/local/tmp..."
  adb push gemma3-270m-it-q8.task /data/local/tmp/
  adb push embeddinggemma-300M_seq1024_mixed-precision.tflite /data/local/tmp/
  adb push sentencepiece.model /data/local/tmp/

  echo "📁 Создаем директорию app_flutter..."
  adb shell "run-as $PACKAGE mkdir -p $APP_DIR"

  echo "📋 Копируем файлы в app_flutter..."
  adb shell "run-as $PACKAGE cp /data/local/tmp/gemma3-270m-it-q8.task $APP_DIR/"
  adb shell "run-as $PACKAGE cp /data/local/tmp/embeddinggemma-300M_seq1024_mixed-precision.tflite $APP_DIR/"
  adb shell "run-as $PACKAGE cp /data/local/tmp/sentencepiece.model $APP_DIR/"

  echo "✅ Проверяем файлы:"
  adb shell "run-as $PACKAGE ls -lh $APP_DIR/"

  echo "🧹 Очищаем /data/local/tmp..."
  adb shell rm /data/local/tmp/gemma3-270m-it-q8.task
  adb shell rm /data/local/tmp/embeddinggemma-300M_seq1024_mixed-precision.tflite
  adb shell rm /data/local/tmp/sentencepiece.model

  echo "✅ Готово! Файлы в $APP_DIR/"
