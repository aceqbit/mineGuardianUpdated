import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/error_guard.dart';

void main() {
  testWidgets('FriendlyError renders a readable message inside a tight layout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 200, child: FriendlyError()))));
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FriendlyError shows the technical message only when given one (debug)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FriendlyError(message: 'RangeError'))));
    expect(find.textContaining('RangeError'), findsOneWidget);
  });

  test('async errors thrown inside ErrorGuard.run are caught and recorded, not crashed', () async {
    ErrorGuard.recent.clear();
    ErrorGuard.run(() {
      Future<void>.delayed(Duration.zero, () => throw StateError('plugin blew up'));
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ErrorGuard.recent.any((l) => l.contains('plugin blew up')), isTrue);
  });
}
