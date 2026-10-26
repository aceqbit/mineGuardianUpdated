import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine_guardian/app/theme/tokens.dart';
import 'package:mine_guardian/contracts/enums.dart';
import 'package:mine_guardian/contracts/socket_events.dart';
import 'package:mine_guardian/core/api/api_client.dart';
import 'package:mine_guardian/core/socket/socket_service.dart';
import 'package:mine_guardian/features/voice_call/bloc/voice_call_bloc.dart';
import 'package:mine_guardian/features/voice_call/data/voice_repository.dart';
import 'package:mine_guardian/features/voice_call/widgets/ai_call_button.dart';

/// POST /api/voice/call answers with [callStatus] (or [error]); /hangup answers COMPLETED.
class _Server implements HttpClientAdapter {
  _Server({this.callStatus = 'QUEUED', this.error});
  final String callStatus;
  final (int, String, Object?)? error;
  final calls = <String>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    ResponseBody json(Object b, [int code = 200]) => ResponseBody.fromString(jsonEncode(b), code, headers: {Headers.contentTypeHeader: ['application/json']});
    calls.add(o.path);
    if (o.path == '/api/voice/call') {
      final e = error;
      if (e != null) return json({'error': {'code': e.$2, 'message': 'refused', 'details': e.$3}}, e.$1);
      return json({'callId': 'c1', 'status': callStatus, 'mode': 'say', 'dryRun': callStatus == 'DRY_RUN', 'targetLabel': 'Sunil (supervisor)', 'statusUpdates': true}, 201);
    }
    if (o.path == '/api/voice/call/c1/hangup') return json({'callId': 'c1', 'status': 'COMPLETED'});
    return json({'error': {'code': 'NOT_FOUND', 'message': 'nf'}}, 404);
  }
}

(ApiClient, SocketService, _Server) _wire(_Server server) {
  final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) async => null, dio: Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = server);
  final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) async => null, url: 'http://x');
  return (api, socket, server);
}

Future<void> until(bool Function() ok) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('refusals are explained in plain words', () {
    expect(voiceErrorText(ApiException(code: 'UNSAFE_DIAL_TARGET', message: 'x', statusCode: 400)), contains('real emergency service'));
    expect(voiceErrorText(ApiException(code: 'CALL_COOLDOWN', message: 'x', statusCode: 429, details: {'retryAfterSec': 12})), contains('12 s'));
    expect(voiceErrorText(ApiException(code: 'NOT_ALLOWLISTED', message: 'x', statusCode: 403)), contains('TWILIO_CALL_ALLOWLIST'));
    expect(voiceErrorText(ApiException(code: 'NO_PHONE', message: 'Sunil has no contact number.', statusCode: 400)), 'Sunil has no contact number.');
  });

  test('a tap places the call at once; live status moves it to speaking, then ended', () async {
    final (api, socket, server) = _wire(_Server());
    final bloc = VoiceCallBloc(repo: VoiceRepository(api: api), socket: socket, targetType: 'user', targetId: 's1')..add(const VoiceCallRequested(reason: 'SOS'));
    await until(() => bloc.state.phase == CallPhase.active);
    expect(server.calls, ['/api/voice/call']);
    socket.inject(SocketEvents.voiceCallStatus, {'callId': 'other', 'status': 'COMPLETED'}, id: 'e1'); // explicit ids: the client dedupes by envelope id
    socket.inject(SocketEvents.voiceCallStatus, {'callId': 'c1', 'status': 'IN_PROGRESS'}, id: 'e2');
    await until(() => bloc.state.status == VoiceCallStatus.inProgress);
    expect(bloc.state.phase, CallPhase.active);
    bloc.add(const VoiceCallHungUp());
    await until(() => bloc.state.phase == CallPhase.done);
    expect(bloc.state.status, VoiceCallStatus.completed);
    await bloc.close();
  });

  test('a refused call ends in an error with the reason, nothing is left ringing', () async {
    final (api, socket, _) = _wire(_Server(error: (400, 'UNSAFE_DIAL_TARGET', null)));
    final bloc = VoiceCallBloc(repo: VoiceRepository(api: api), socket: socket, targetType: 'user', targetId: 'x')..add(const VoiceCallRequested());
    await until(() => bloc.state.phase == CallPhase.error);
    expect(bloc.state.message, contains('real emergency service'));
    expect(bloc.state.callId, isNull);
    await bloc.close();
  });

  for (final dark in [false, true]) {
    testWidgets('AI call button at 360px dark=$dark: one tap -> dry-run status with no overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (api, socket, server) = _wire(_Server(callStatus: 'DRY_RUN'));
      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light, extensions: [dark ? MgColors.dark : MgColors.light]),
          home: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: AiCallButton(targetType: 'user', targetId: 's1', targetLabel: 'Sunil Banerjee', expand: true))),
        ),
      ));
      await tester.tap(find.text('AI call Sunil Banerjee'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(server.calls, ['/api/voice/call'], reason: 'no confirm dialog: the tap is the call');
      expect(find.text('Dry run — no real call placed'), findsOneWidget);
      expect(find.text('Call Sunil Banerjee again'), findsOneWidget);
    });
  }

  testWidgets('the sheet from a compact card places the call as it opens', (tester) async {
    final (api, socket, server) = _wire(_Server());
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [RepositoryProvider<ApiClient>.value(value: api), RepositoryProvider<SocketService>.value(value: socket)],
      child: MaterialApp(
        theme: ThemeData(extensions: const [MgColors.light]),
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => showAiCallSheet(ctx, targetType: 'contact', targetId: 'k1', targetLabel: 'Mine Rescue'), child: const Text('AI agent'))))),
      ),
    ));
    await tester.tap(find.text('AI agent'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(server.calls, ['/api/voice/call']);
    expect(find.text('Hang up'), findsOneWidget);
    await tester.tap(find.text('Hang up'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Call ended'), findsOneWidget);
  });
}
