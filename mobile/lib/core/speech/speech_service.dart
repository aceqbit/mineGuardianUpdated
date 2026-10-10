import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// What the speaker is doing right now. [index] is the segment being read (null when idle).
class SpeechState {
  const SpeechState({this.speaking = false, this.index, this.owner});
  final bool speaking;
  final int? index;

  /// Identifies who started the speech so only that button shows "stop".
  final String? owner;

  static const idle = SpeechState();
}

/// Text-to-speech behind a small interface so screens and tests never touch the plugin.
abstract class SpeechService {
  /// Process-wide instance; tests assign a fake.
  static SpeechService instance = FlutterTtsSpeechService();

  ValueListenable<SpeechState> get state;

  /// Reads [segments] one after another. Replaces anything already being read. Never throws.
  Future<void> speak(List<String> segments, {required String owner});

  Future<void> stop();
}

/// flutter_tts implementation (en-IN, falls back to the engine default). Works offline on Android / iOS and on web.
class FlutterTtsSpeechService implements SpeechService {
  FlutterTtsSpeechService({FlutterTts? tts}) : _tts = tts;

  FlutterTts? _tts;
  bool _ready = false;
  bool _broken = false;
  int _run = 0;
  Completer<void>? _segmentDone;
  final _state = ValueNotifier<SpeechState>(SpeechState.idle);

  @override
  ValueListenable<SpeechState> get state => _state;

  Future<bool> _init() async {
    if (_broken) return false;
    if (_ready) return true;
    try {
      final t = _tts ??= FlutterTts();
      await t.setLanguage('en-IN');
      await t.setSpeechRate(0.45);
      await t.setVolume(1.0);
      await t.setPitch(1.0);
      await t.awaitSpeakCompletion(false);
      t.setCompletionHandler(() => _segmentDone?.complete());
      t.setCancelHandler(() => _segmentDone?.complete());
      t.setErrorHandler((_) => _segmentDone?.complete());
      _ready = true;
      return true;
    } catch (_) {
      _broken = true;
      return false;
    }
  }

  @override
  Future<void> speak(List<String> segments, {required String owner}) async {
    final run = ++_run;
    final items = segments.where((s) => s.trim().isNotEmpty).toList();
    if (items.isEmpty || !await _init()) {
      _state.value = SpeechState.idle;
      return;
    }
    try {
      await _tts!.stop();
    } catch (_) {}
    for (var i = 0; i < items.length; i++) {
      if (run != _run) return; // superseded or stopped
      _state.value = SpeechState(speaking: true, index: i, owner: owner);
      _segmentDone = Completer<void>();
      try {
        await _tts!.speak(items[i]);
        await _segmentDone!.future.timeout(const Duration(seconds: 60));
      } catch (_) {
        break;
      }
    }
    if (run == _run) _state.value = SpeechState.idle;
  }

  @override
  Future<void> stop() async {
    _run++;
    _state.value = SpeechState.idle;
    _segmentDone?.complete();
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
