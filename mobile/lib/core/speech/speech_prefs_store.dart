import '../db/cache_repository.dart';
import 'speech_service.dart';

/// Saves and restores the voice choice in the local key/value cache so it survives restarts.
class SpeechPrefsStore {
  SpeechPrefsStore(this._cache);
  final CacheRepository _cache;

  static const _key = 'speech_prefs';

  Future<SpeechPrefs> load() async {
    try {
      final raw = await _cache.read(_key);
      if (raw is! Map) return const SpeechPrefs();
      final speed = SpeechSpeed.values.where((s) => s.name == raw['speed']).firstOrNull ?? SpeechSpeed.normal;
      final name = raw['voiceName'];
      final voice = name is String && name.isNotEmpty ? SpeechVoice(name: name, locale: '${raw['voiceLocale'] ?? ''}') : null;
      return SpeechPrefs(voice: voice, speed: speed);
    } catch (_) {
      return const SpeechPrefs();
    }
  }

  Future<void> save(SpeechPrefs p) async {
    try {
      await _cache.write(_key, {'speed': p.speed.name, 'voiceName': p.voice?.name, 'voiceLocale': p.voice?.locale});
    } catch (_) {}
  }

  /// Applies saved choices to the shared speech service. Call once at start-up.
  static Future<void> restore(CacheRepository cache, {SpeechService? service}) async {
    final p = await SpeechPrefsStore(cache).load();
    await (service ?? SpeechService.instance).configure(p);
  }
}
