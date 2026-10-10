import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/app_images.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/app/ui/media_tile.dart';
import 'package:mine_guardian/app/ui/tile_art.dart';

void main() {
  test('every AppImages entry maps to its own illustration', () {
    final kinds = {for (final e in AppImages.all.entries) e.key: tileArtFor(e.value)};
    expect(kinds['capture'], TileArtKind.capture);
    expect(kinds['hazard'], TileArtKind.hazard);
    expect(kinds['leaderboard'], TileArtKind.leaderboard);
    expect(kinds['rewards'], TileArtKind.rewards);
    expect(kinds['adminCrisis'], TileArtKind.crisis);
    expect(tileArtFor('https://example.com/unknown.jpg'), TileArtKind.hero);
  });

  for (final size in const [Size(360, 740), Size(768, 1024), Size(1280, 800)]) {
    for (final dark in [false, true]) {
      testWidgets('tiles show their drawn art with no network at ${size.width.toInt()}px dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]),
          home: Scaffold(
            body: GridView.count(crossAxisCount: size.width < 600 ? 1 : 3, childAspectRatio: 1.3, children: [
              for (final e in AppImages.all.entries) MediaTile(imageUrl: e.value, icon: Icons.shield, title: e.key, subtitle: 'sub'),
            ]),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(TileArt), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
