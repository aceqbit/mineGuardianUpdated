import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/core/maps/google_tiles.dart';
import 'package:mine_guardian/core/models/mine_layout.dart';
import 'package:mine_guardian/features/sos/data/evac_graph.dart';
import 'package:mine_guardian/features/sos/data/nav_logic.dart';

import 'fixtures/layout_fixture.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);
  final Map<String, dynamic> body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final layout = MineLayoutData.fromJson(jsonDecode(layoutFixtureJson) as Map<String, dynamic>);
  final graph = EvacGraph.build(layout);
  GeoPoint j(String id) => layout.junctions.firstWhere((x) => x.id == id).point;

  group('routes between a chosen start and end', () {
    final start = graph.nearestJunction(j('J5'))!;
    final exit = layout.exits.first;

    test('a destination gets several different routes, shortest first, none sharing more than 70%', () {
      final routes = graph.routesBetween(start, exit);
      expect(routes.length, greaterThan(1));
      expect(routes.map((r) => r.key).toSet().length, routes.length);
      for (var i = 1; i < routes.length; i++) {
        expect(routes[i].distanceM, greaterThanOrEqualTo(routes[i - 1].distanceM));
      }
      for (final a in routes) {
        expect(a.nodes.first, start);
        expect(a.nodes.last, exit.node);
        for (final b in routes) {
          if (!identical(a, b)) expect(EvacGraph.overlap(a, b), lessThanOrEqualTo(0.7));
        }
      }
    });

    test('the first route is the true shortest path', () {
      expect(graph.routesBetween(start, exit).first.distanceM, closeTo(graph.routeToExit(start, exit.id)!.distanceM, 0.01));
    });

    test('a refuge chamber is a valid end', () {
      final refuge = graph.destination(layout.refuges.first.id)!;
      expect(refuge.exitType, 'refuge');
      expect(graph.routesBetween(start, refuge), isNotEmpty);
    });

    test('blocked tunnels are never used and an unreachable end gives no routes', () {
      final blockedAll = EvacGraph.build(layout, extraBlocked: layout.tunnels.map((t) => t.id).toSet());
      expect(blockedAll.routesBetween(start, exit), isEmpty);
    });

    test('chooseTarget uses the chosen destination and the worker can pick a specific route by key', () {
      final c = chooseTarget(graph: graph, from: j('J5'), designatedExitId: null, workerPickedExitId: null, destinationId: exit.id);
      expect(c.alternatives.every((r) => r.exit.id == exit.id), isTrue);
      expect(c.reason, TargetReason.workerChoice);
      expect(c.route!.key, c.alternatives.first.key);
      final second = c.alternatives.last;
      final picked = chooseTarget(graph: graph, from: j('J5'), designatedExitId: null, workerPickedExitId: second.key, destinationId: exit.id);
      expect(picked.route!.key, second.key);
    });

    test('with no destination the behaviour is unchanged (one route per exit)', () {
      final c = chooseTarget(graph: graph, from: j('J5'), designatedExitId: null, workerPickedExitId: null);
      expect(c.alternatives.map((r) => r.exit.id).toSet().length, c.alternatives.length);
    });
  });

  group('GoogleTiles', () {
    test('without an API key there are no tiles and nothing is requested', () async {
      final dio = Dio()..httpClientAdapter = _StubAdapter({});
      expect(await GoogleTiles(dio: dio, apiKey: '').template(), isNull);
      expect((dio.httpClientAdapter as _StubAdapter).last, isNull);
    });

    test('with a key it creates one session and builds the tile template', () async {
      final adapter = _StubAdapter({'session': 'abc123', 'expiry': '${DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch ~/ 1000}'});
      final tiles = GoogleTiles(dio: Dio()..httpClientAdapter = adapter, apiKey: 'KEY');
      final t = await tiles.template();
      expect(t, 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=abc123&key=KEY');
      expect(adapter.last!.uri.queryParameters['key'], 'KEY');
      adapter.last = null;
      expect(await tiles.template(), t); // cached: no second request
      expect(adapter.last, isNull);
    });
  });
}
