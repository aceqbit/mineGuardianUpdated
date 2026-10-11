import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/auth/auth_repository.dart';
import 'package:mine_guardian/core/auth/session_bloc.dart';
import 'package:mine_guardian/core/location/location_service.dart';
import 'package:mine_guardian/core/models/mine_layout.dart';
import 'package:mine_guardian/core/models/sample_layout.dart';
import 'package:mine_guardian/features/sos/bloc/sos_state.dart';
import 'package:mine_guardian/features/sos/data/evac_graph.dart';

class _User implements User {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Auth implements AuthRepository {
  _Auth(this.user);
  User? user;
  int signOuts = 0;
  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signOuts++;
    user = null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('sample map (shown when the real layout is not available)', () {
    final layout = sampleLayout();

    test('it is marked as a sample and is a complete mine: exits, a refuge, zones, tunnels', () {
      expect(layout.version, sampleLayoutVersion);
      expect(SosState(layout: layout).isSample, isTrue);
      expect(layout.exits.length, greaterThanOrEqualTo(3));
      expect(layout.refuges, isNotEmpty);
      expect(layout.zones.map((z) => z.code), containsAll(['Z-A', 'Z-B', 'Z-C']));
      expect(layout.tunnels.length, greaterThanOrEqualTo(30));
    });

    test('it always has a sample start (zone centre) and routes to the exits, so the map is never empty', () {
      final graph = EvacGraph.build(layout);
      final routes = graph.routeFromZone('Z-B');
      expect(routes, isNotNull);
      expect(graph.alternativesFrom(layout.zones.firstWhere((z) => z.code == 'Z-B').ring.first), isNotEmpty);
    });

    test('a real layout is not a sample', () {
      final real = MineLayoutData(version: 1, anchor: layout.anchor, zones: layout.zones, tunnels: layout.tunnels, junctions: layout.junctions, exits: layout.exits, refuges: layout.refuges);
      expect(SosState(layout: real).isSample, isFalse);
    });

    test('a GPS fix far from the mine (a laptop at home) is outside the mine and gives no off-route or distance numbers', () {
      LocationFix fix(double lat, double lng) => LocationFix(lat: lat, lng: lng, accuracyM: 10, ts: DateTime.now());
      final far = SosState(layout: layout, fix: fix(13.08, 80.27));
      expect(far.fixOutsideMine, isTrue);
      expect(far.offRouteM, isNull);
      expect(far.distanceToTargetM, isNull);
      final near = SosState(layout: layout, fix: fix(layout.anchor.lat, layout.anchor.lng));
      expect(near.fixOutsideMine, isFalse);
    });
  });

  group('every app start begins at login', () {
    test('a session kept from last time is ended, so the emailed code is always required', () async {
      final auth = _Auth(_User());
      final bloc = SessionBloc(auth: auth, api: ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null));
      bloc.add(const AppStarted());
      await bloc.stream.firstWhere((s) => s is! SessionUnknown);
      expect(bloc.state, isA<SessionUnauthenticated>());
      expect(auth.signOuts, 1);
      await bloc.close();
    });

    test('with no session it simply shows login', () async {
      final auth = _Auth(null);
      final bloc = SessionBloc(auth: auth, api: ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null));
      bloc.add(const AppStarted());
      await bloc.stream.firstWhere((s) => s is! SessionUnknown);
      expect(bloc.state, isA<SessionUnauthenticated>());
      expect(auth.signOuts, 0);
      await bloc.close();
    });
  });
}
