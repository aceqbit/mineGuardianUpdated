/// A voice the device offers (flutter_tts `getVoices` entry).
class SpeechVoice {
  const SpeechVoice({required this.name, required this.locale});
  final String name;
  final String locale;

  Map<String, String> toMap() => {'name': name, 'locale': locale};

  @override
  bool operator ==(Object other) => other is SpeechVoice && other.name == name && other.locale == locale;
  @override
  int get hashCode => Object.hash(name, locale);
}

const _warmNames = ['neerja', 'heera', 'aria', 'jenny', 'sonia', 'libby', 'samantha', 'karen', 'veena', 'google uk english female', 'google us english'];

/// Higher is nicer. Prefers neural/natural/network voices, Indian English first, then other English.
/// Pure so it can be unit-tested; the platform decides which voices exist. Non-English voices score -1.
int scoreVoice(SpeechVoice v) {
  final n = v.name.toLowerCase();
  final l = v.locale.toLowerCase().replaceAll('_', '-');
  if (!l.startsWith('en')) return -1;
  var s = 0;
  if (l == 'en-in') {
    s += 40;
  } else if (l == 'en-gb' || l == 'en-au') {
    s += 25;
  } else if (l == 'en-us') {
    s += 20;
  } else {
    s += 10;
  }
  if (n.contains('natural') || n.contains('neural') || n.contains('online')) s += 60;
  if (n.contains('network')) s += 35; // Android high-quality network voices
  if (n.contains('enhanced') || n.contains('premium')) s += 30;
  if (_warmNames.any(n.contains)) s += 15;
  if (n.contains('espeak') || n.contains('compact') || n.contains('default')) s -= 40;
  return s < 0 ? 0 : s;
}

/// The best voice from [all], or null when none is English.
SpeechVoice? pickBestVoice(List<SpeechVoice> all) {
  SpeechVoice? best;
  var bestScore = -1;
  for (final v in all) {
    final s = scoreVoice(v);
    if (s > bestScore) {
      bestScore = s;
      best = v;
    }
  }
  return best;
}

/// English voices sorted best first, for the voice picker.
List<SpeechVoice> rankedEnglishVoices(List<SpeechVoice> all) {
  final list = all.where((v) => scoreVoice(v) >= 0).toList()..sort((a, b) => scoreVoice(b).compareTo(scoreVoice(a)));
  return list;
}

/// Splits text into sentences so each is spoken with a natural pause.
List<String> splitSentences(String text) {
  final parts = text.split(RegExp(r'(?<=[.!?])\s+|\n+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? [text.trim()].where((s) => s.isNotEmpty).toList() : parts;
}
