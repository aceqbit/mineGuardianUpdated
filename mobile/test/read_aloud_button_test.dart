import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/app_theme.dart';
import 'package:mine_guardian/app/ui/read_aloud_button.dart';
import 'package:mine_guardian/core/speech/speech_service.dart';

class _FakeSpeech implements SpeechService {
  final _s = ValueNotifier<SpeechState>(SpeechState.idle);
  List<String> spoken = const [];
  int stops = 0;

  @override
  ValueListenable<SpeechState> get state => _s;
  @override
  ValueListenable<SpeechPrefs> get prefs => ValueNotifier(const SpeechPrefs());
  @override
  Future<List<SpeechVoice>> voices() async => const [];
  @override
  Future<void> configure(SpeechPrefs prefs) async {}

  @override
  Future<void> speak(List<String> segments, {required String owner}) async {
    spoken = segments;
    _s.value = SpeechState(speaking: true, index: 0, owner: owner);
  }

  @override
  Future<void> stop() async {
    stops++;
    _s.value = SpeechState.idle;
  }
}

void main() {
  testWidgets('tap reads aloud, tap again stops, dispose stops own speech', (tester) async {
    final fake = _FakeSpeech();
    Widget app(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: child)));

    await tester.pumpWidget(app(ReadAloudButton(owner: 'a', label: 'Read aloud', segments: const ['one', 'two'], service: fake)));
    await tester.tap(find.text('Read aloud'));
    await tester.pump();
    expect(fake.spoken, ['one', 'two']);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(fake.stops, 1);
    expect(find.text('Read aloud'), findsOneWidget);

    await tester.tap(find.text('Read aloud'));
    await tester.pump();
    await tester.pumpWidget(app(const SizedBox()));
    expect(fake.stops, 2);
  });
}
