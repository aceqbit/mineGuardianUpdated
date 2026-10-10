import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/core/speech/voice_ranking.dart';

void main() {
  const natural = SpeechVoice(name: 'Microsoft Neerja Online (Natural) - English (India)', locale: 'en-IN');
  const robotic = SpeechVoice(name: 'espeak default', locale: 'en-US');
  const gb = SpeechVoice(name: 'Google UK English Female', locale: 'en-GB');
  const hindi = SpeechVoice(name: 'Google Hindi', locale: 'hi-IN');
  const androidNet = SpeechVoice(name: 'en-in-x-ahp-network', locale: 'en-IN');

  test('natural Indian-English voice beats robotic and non-English voices', () {
    expect(pickBestVoice([robotic, hindi, natural, gb]), natural);
    expect(scoreVoice(hindi), -1);
  });

  test('android network voice beats an unmarked local voice', () {
    const local = SpeechVoice(name: 'en-in-x-ene-local', locale: 'en-IN');
    expect(pickBestVoice([local, androidNet]), androidNet);
  });

  test('ranked list drops non-English and sorts best first', () {
    final r = rankedEnglishVoices([hindi, robotic, natural, gb]);
    expect(r.first, natural);
    expect(r, isNot(contains(hindi)));
    expect(pickBestVoice([hindi]), isNull);
  });

  test('sentences split for natural pauses', () {
    expect(splitSentences('Stay calm. Walk to the exit! Report to your supervisor.'), ['Stay calm.', 'Walk to the exit!', 'Report to your supervisor.']);
    expect(splitSentences('One line'), ['One line']);
    expect(splitSentences('   '), isEmpty);
  });
}
