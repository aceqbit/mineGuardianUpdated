import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'voice_ranking.dart';

export 'voice_ranking.dart' show SpeechVoice;

/// What the speaker is doing right now. [index] is the segment being read (null when idle).
class SpeechState {
  const SpeechState({this.speaking = false, this.index, this.owner});
  final bool speaking;
  final int? index;

  /// Identifies who started the speech so only that button shows "stop".
  final String? owner;

  static const idle = SpeechState();
}

enum SpeechSpeed {
  slow('Slow', 0.85),
  normal('Normal', 1.0),
  fast('Fast', 1.2);

  const SpeechSpeed(this.label, this.factor);
  final String label;
  final double factor;
}

/// User choices for the voice. Persisted by the caller (see `SpeechPrefsStore`).
class SpeechPrefs {
  const SpeechPrefs({this.voice, this.speed = SpeechSpeed.normal});
  final SpeechVoice? voice;
  final SpeechSpeed speed;

  SpeechPrefs copyWith({SpeechVoice? voice, bool clearVoice = false, SpeechSpeed? speed}) => SpeechPrefs(voice: clearVoice ? null : (voice ?? this.voice), speed: speed ?? this.speed);
}

/// Text-to-speech behind a small interface so screens and tests never touch the plugin.
abstract class SpeechService {
  /// Process-wide instance; tests assign a fake.
  static SpeechService instance = FlutterTtsSpeechService();

  ValueListenable<SpeechState> get state;
  ValueListenable<SpeechPrefs> get prefs;

  /// Reads [segments] one after another, sentence by sentence. Replaces anything already being read. Never throws.
  Future<void> speak(List<String> segments, {required String owner});

  Future<void> stop();

  /// English voices installed on this device, best first. Empty when the engine reports none.
  Future<List<SpeechVoice>> voices();

  /// Applies new choices (takes effect on the next sentence).
  Future<void> configure(SpeechPrefs prefs);
}

/// flutter_tts implementation. The rate scale differs per platform (web 1.0 = normal, Android/iOS 0.5 = normal),
/// so each gets its own base. The best installed English voice is chosen automatically unless the user picked one.
class FlutterTtsSpeechService implements SpeechService {
  FlutterTtsSpeechService({FlutterTts? tts}) : _tts = tts;

  FlutterTts? _tts;
  bool _ready = false;
  bool _broken = false;
  int _run = 0;
  Completer<void>? _segmentDone;
  List<SpeechVoice>? _voices;
  final _state = ValueNotifier<SpeechState>(SpeechState.idle);
  final _prefs = ValueNotifier<SpeechPrefs>(const SpeechPrefs());

  @override
  ValueListenable<SpeechState> get state => _state;
  @override
  ValueListenable<SpeechPrefs> get prefs => _prefs;

  static double get _baseRate {
    if (kIsWeb) return 1.0;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 0.52,
      _ => 0.5,
    };
  }

  Future<bool> _init() async {
    if (_broken) return false;
    if (_ready) return true;
    try {
      final t = _tts ??= FlutterTts();
      await t.setLanguage('en-IN');
      await t.setVolume(1.0);
      await t.setPitch(1.0);
      await t.awaitSpeakCompletion(false);
      t.setCompletionHandler(() => _segmentDone?.complete());
      t.setCancelHandler(() => _segmentDone?.complete());
      t.setErrorHandler((_) => _segmentDone?.complete());
      _ready = true;
      await _applyVoice();
      return true;
    } catch (_) {
      _broken = true;
      return false;
    }
  }

  Future<void> _applyVoice() async {
    try {
      final chosen = _prefs.value.voice ?? pickBestVoice(await voices());
      if (chosen != null) await _tts!.setVoice(chosen.toMap());
    } catch (_) {}
  }

  @override
  Future<List<SpeechVoice>> voices() async {
    if (_voices != null) return _voices!;
    try {
      final t = _tts ??= FlutterTts();
      final raw = await t.getVoices;
      final all = <SpeechVoice>[];
      if (raw is List) {
        for (final v in raw) {
          if (v is Map && v['name'] != null) all.add(SpeechVoice(name: '${v['name']}', locale: '${v['locale'] ?? ''}'));
        }
      }
      return _voices = rankedEnglishVoices(all);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> configure(SpeechPrefs prefs) async {
    final voiceChanged = prefs.voice != _prefs.value.voice;
    _prefs.value = prefs;
    if (_ready && voiceChanged) await _applyVoice();
  }

  @override
  Future<void> speak(List<String> segments, {required String owner}) async {
    final run = ++_run;
    final items = [for (final s in segments) ...splitSentences(s)];
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
        await _tts!.setSpeechRate((_baseRate * _prefs.value.speed.factor).clamp(0.1, kIsWeb ? 2.0 : 1.0));
        await _tts!.speak(items[i]);
        await _segmentDone!.future.timeout(const Duration(seconds: 60));
        if (i < items.length - 1) await Future<void>.delayed(const Duration(milliseconds: 220)); // natural pause between sentences
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
