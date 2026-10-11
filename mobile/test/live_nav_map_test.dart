import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/app_theme.dart';
import 'package:mine_guardian/core/location/location_service.dart';
import 'package:mine_guardian/core/models/mine_layout.dart';
import 'package:mine_guardian/features/sos/bloc/sos_state.dart';
import 'package:mine_guardian/features/sos/data/evac_graph.dart';
import 'package:mine_guardian/features/sos/data/nav_logic.dart';
import 'package:mine_guardian/features/sos/widgets/live_nav_map.dart';

import 'fixtures/layout_fixture.dart';

void main() {
  final layout = MineLayoutData.fromJson(jsonDecode(layoutFixtureJson) as Map<String, dynamic>);
  final g = EvacGraph.build(layout);
  final here = layout.junctions.firstWhere((j) => j.id == 'J5').point;
  final alts = g.alternativesFrom(here);

  SosState state(GeoPoint at) => SosState(
        layout: layout,
        zoneCode: 'Z-B',
        fix: LocationFix(lat: at.lat, lng: at.lng, accuracyM: 8, ts: DateTime.utc(2026)),
        alternatives: alts,
        offlineRoute: alts.first,
        selectedExitId: alts.first.exit.id,
      );

  for (final size in const [Size(360, 640), Size(768, 900), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('live map shows target and route chips at ${size.width.toInt()}px dark=$dark without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        String? picked;
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(body: SizedBox(width: size.width, height: size.height - 100, child: LiveNavMap(state: state(here), onSelectRoute: (id) => picked = id))),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Go to '), findsOneWidget);
        expect(find.textContaining('TARGET'), findsOneWidget);
        if (alts.length > 1) {
          await tester.ensureVisible(find.textContaining('Route B'));
          await tester.pump();
          await tester.tap(find.textContaining('Route B'));
          expect(picked, alts[1].key);
        }
      });
    }
  }

  testWidgets('off-route and arrived states are announced', (tester) async {
    final far = GeoPoint(here.lat + 0.001, here.lng);
    expect(state(far).offRoute, isTrue);
    final arrived = state(alts.first.exit.point);
    expect(arrived.arrived, isTrue);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: SizedBox(width: 400, height: 700, child: LiveNavMap(state: arrived, onSelectRoute: (_) {})))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('You have reached'), findsOneWidget);
  });

  testWidgets('shows why the target was chosen, the next turn, and the simulate control', (tester) async {
    var toggled = 0;
    final s = SosState(
      layout: layout,
      zoneCode: 'Z-B',
      fix: LocationFix(lat: here.lat, lng: here.lng, accuracyM: 8, ts: DateTime.utc(2026), headingDeg: 90),
      alternatives: alts,
      offlineRoute: alts.first,
      selectedExitId: alts.first.exit.id,
      targetReason: TargetReason.designated,
      evacOnly: true,
    );
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: SizedBox(width: 420, height: 760, child: LiveNavMap(state: s, onSelectRoute: (_) {}, onToggleSimulate: () => toggled++)))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Emergency exit set by your admin'), findsOneWidget);
    expect(find.textContaining(RegExp(r'In [0-9]+ m:')), findsOneWidget);
    await tester.tap(find.byTooltip('Simulate walk to the exit'));
    expect(toggled, 1);
  });
}
