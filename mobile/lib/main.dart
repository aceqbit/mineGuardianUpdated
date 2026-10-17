import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/error_guard.dart';
import 'core/api/api_client.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/session_bloc.dart';
import 'core/db/cache_repository.dart';
import 'core/db/layout_repository.dart';
import 'core/db/local_db.dart';
import 'core/location/live_tracker.dart';
import 'core/location/tracking_controller.dart';
import 'core/socket/socket_service.dart';
import 'core/speech/speech_prefs_store.dart';
import 'core/sync/api_outbox_sender.dart';
import 'core/sync/outbox_queue.dart';
import 'core/sync/reachability.dart';
import 'core/sync/sync_engine.dart';
import 'firebase_options.dart';

void main() {
  ErrorGuard.run(() {
    ErrorGuard.install();
    _boot();
  });
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    runApp(_ConfigError(message: '$e'));
    return;
  }

  final auth = AuthRepository();
  final api = ApiClient(tokenProvider: ({bool forceRefresh = false}) => auth.idToken(forceRefresh: forceRefresh));
  final socket = SocketService(tokenProvider: ({bool forceRefresh = false}) => auth.idToken(forceRefresh: forceRefresh));
  final session = SessionBloc(auth: auth, api: api);
  final db = await LocalDb.open();
  final engine = SyncEngine(outbox: db.outbox, sender: ApiOutboxSender(api: api, socket: socket), reachability: ConnectivityReachability(api: api), onRemoved: OutboxQueue.deleteFile);
  final queue = OutboxQueue(outbox: db.outbox, engine: engine);
  await SpeechPrefsStore.restore(db.cache); // saved voice and speed for read-aloud
  // Add-on X3: live GPS + motion-sensor tracking for miners (shift window / crisis, after consent).
  final tracking = TrackingController(session: session, socket: socket, cache: db.cache, api: api, tracker: LiveTracker(socket: socket, queue: queue, layouts: LayoutRepository(api: api, cache: db.cache)))..start();

  runApp(MultiRepositoryProvider(
    providers: [
      RepositoryProvider<AuthRepository>.value(value: auth),
      RepositoryProvider<ApiClient>.value(value: api),
      RepositoryProvider<SocketService>.value(value: socket),
      RepositoryProvider<CacheRepository>.value(value: db.cache),
      RepositoryProvider<SyncEngine>.value(value: engine),
      RepositoryProvider<OutboxQueue>.value(value: queue),
      RepositoryProvider<TrackingController>.value(value: tracking),
    ],
    child: BlocProvider<SessionBloc>.value(
      value: session,
      child: MineGuardianApp(session: session, socket: socket, engine: engine),
    ),
  ));
}

class _ConfigError extends StatelessWidget {
  const _ConfigError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Setup needed\n\n$message', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
