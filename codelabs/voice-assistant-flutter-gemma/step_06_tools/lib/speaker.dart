import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'wav.dart';

/// Plays clips one after another, and can drop all of them at once.
///
/// A streamed reply arrives as several clips — one per clause — while the
/// model is still writing the next. They have to play in order, without
/// overlapping, and a barge-in has to silence the one playing AND every one
/// still waiting.
class Speaker {
  final _player = AudioPlayer();

  /// The end of the queue. Each clip is chained onto it, so it starts only
  /// when the one before it has finished.
  Future<void> _tail = Future.value();

  /// Bumped by [stop]. A clip remembers the value it was queued under and
  /// plays only if nothing has stopped the speaker since.
  int _generation = 0;
  int _clip = 0;

  /// Queues 16-bit mono [pcm]. Returns at once; the clip plays when its turn
  /// comes.
  void enqueue(Uint8List pcm, int sampleRate) {
    // The last event of a streamed reply is an empty "that was all" marker.
    if (pcm.isEmpty) return;
    final generation = _generation;
    final name = 'reply_${_clip++}.wav';
    _tail = _tail
        .then((_) async {
          if (generation != _generation) return;
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/$name');
          await file.writeAsBytes(wavFromPcm16(pcm, sampleRate: sampleRate));
          if (generation != _generation) return;
          // After a clip ends the player still reports `playing`, and `play()`
          // on a playing player returns at once without playing anything.
          // Stopping first puts it back where `play()` means "play this".
          await _player.stop();
          await _player.setFilePath(file.path);
          // Completes when this clip ends — or when [stop] cuts it off.
          await _player.play();
          await file.delete();
        })
        // One clip that fails to play must not take every later one with it.
        .catchError((Object _) {});
  }

  /// Silences the clip that is playing and drops every one still queued.
  Future<void> stop() async {
    _generation++;
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
}
