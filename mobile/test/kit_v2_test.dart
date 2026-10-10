import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/app/ui/mg_hero_header.dart';
import 'package:mine_guardian/app/ui/score_ring.dart';
import 'package:mine_guardian/app/ui/success_burst.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/core/time/ist.dart';

Widget _host(Widget child, {bool dark = false, bool reduce = false}) => MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]),
      builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: w!),
      home: Scaffold(body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(Space.lg), child: child))),
    );

void main() {
  group('shift progress', () {
    DateTime wall(int h, int m) => DateTime.utc(2026, 1, 5, h, m);

    test('shift A at 10:00 is half way with 4 h left', () {
      final p = shiftProgress(Shift.a, wall(10, 0));
      expect(p.open, isTrue);
      expect(p.fraction, closeTo(0.5, 1e-9));
      expect(p.minutesLeft, 240);
    });

    test('outside the window the shift is closed', () {
      final p = shiftProgress(Shift.a, wall(15, 0));
      expect(p.open, isFalse);
      expect(p.fraction, 0);
    });

    test('shift C wraps midnight both sides', () {
      final late = shiftProgress(Shift.c, wall(23, 0));
      final early = shiftProgress(Shift.c, wall(2, 0));
      expect(late.open, isTrue);
      expect(early.open, isTrue);
      expect(late.fraction, closeTo(1 / 8, 1e-9));
      expect(early.fraction, closeTo(4 / 8, 1e-9));
      expect(early.minutesLeft, 240);
      expect(shiftProgress(Shift.c, wall(12, 0)).open, isFalse);
    });

    test('greetings by hour', () {
      expect(greetingFor(wall(8, 0)), 'Good morning');
      expect(greetingFor(wall(13, 0)), 'Good afternoon');
      expect(greetingFor(wall(18, 0)), 'Good evening');
      expect(greetingFor(wall(2, 0)), 'Stay safe tonight');
    });
  });

  for (final size in const [Size(360, 740), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('hero, ring and burst fit at ${size.width.toInt()}px dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          dark: dark,
          Column(children: [
            MgHeroHeader(eyebrow: 'GOOD MORNING', title: 'Hi Dinesh', subtitle: 'Z-B · Central Panel', trailing: const ScoreRing(value: 640, size: 88, label: 'score', onDark: true), child: const Text('child', style: TextStyle(color: Colors.white))),
            const SizedBox(height: Space.lg),
            const ScoreRing(value: null),
            const SizedBox(height: Space.lg),
            const SuccessBurst(size: 96),
          ]),
        ));
        await tester.pump(const Duration(milliseconds: 1500));
        expect(tester.takeException(), isNull);
        expect(find.text('Hi Dinesh'), findsOneWidget);
        expect(find.text('640'), findsOneWidget);
        expect(find.text('—'), findsOneWidget); // no data: neutral, never an invented number
      });
    }
  }

  testWidgets('with reduced motion the ring and burst show their final state at once', (tester) async {
    await tester.pumpWidget(_host(reduce: true, const Column(children: [ScoreRing(value: 500), SuccessBurst(size: 80)])));
    await tester.pump();
    expect(find.text('500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
