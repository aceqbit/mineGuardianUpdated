import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../contracts/enums.dart';
import '../contracts/routes.dart';
import '../core/auth/session_bloc.dart';
import '../features/admin_home/view/admin_home_screen.dart';
import '../features/auth/view/login_screen.dart';
import '../features/auth/view/signup_screen.dart';
import '../features/sos/view/sos_screen.dart';
import '../features/splash/view/splash_screen.dart';
import '../features/supervisor_home/data/models/feed_item.dart';
import '../features/supervisor_home/view/hazard_detail_screen.dart';
import '../features/supervisor_home/view/supervisor_home_screen.dart';
import '../features/worker/view/capture_screen.dart';
import '../features/worker/view/hazard_report_screen.dart';
import '../features/worker/view/worker_home_screen.dart';
import 'ui/page_transitions.dart';
import '../phase2/phase2_routes.dart';
import '../features/dev_gallery/view/ui_gallery_screen.dart';
import 'global_overlays.dart';

/// Makes GoRouter re-run `redirect` whenever the session changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class ScreenPlaceholder extends StatelessWidget {
  const ScreenPlaceholder(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Text(title)));
}

String? sessionRedirect(SessionState session, String loc) {
  if (loc.startsWith('/dev/')) return kDebugMode ? null : Routes.login;
  if (session is SessionUnknown) return loc == Routes.splash ? null : Routes.splash;
  if (session is SessionUnauthenticated) {
    return (loc == Routes.login || loc == Routes.signup) ? null : Routes.login;
  }
  final user = (session as SessionAuthenticated).user;
  final home = Routes.homeFor(user.role.wire);
  if (loc == Routes.splash || loc == Routes.login || loc == Routes.signup) return home;
  bool under(String p) => loc == p || loc.startsWith('$p/');
  if (under('/worker') && user.role != Role.miner) return home;
  if (under('/supervisor') && user.role != Role.supervisor) return home;
  if (under('/admin') && user.role != Role.admin) return home;
  if (loc == Routes.crisisView && user.role == Role.miner) return home;
  return null;
}

/// Screens are plugged in by their steps; `extraRoutes` lets features register themselves.
GoRouter buildRouter(SessionBloc session, {List<RouteBase> extraRoutes = const []}) {
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: GoRouterRefreshStream(session.stream),
    redirect: (context, state) => sessionRedirect(session.state, state.uri.path),
    errorBuilder: (context, state) => const SplashScreen(),
    routes: [
      ShellRoute(
        builder: (context, state, child) => GlobalOverlays(child: child),
        routes: [
          GoRoute(path: Routes.splash, builder: (c, s) => const SplashScreen()),
          GoRoute(path: Routes.login, pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const LoginScreen())),
          GoRoute(path: Routes.signup, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: const SignupScreen())),
          GoRoute(path: Routes.worker, pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const WorkerHomeScreen())),
          GoRoute(path: Routes.workerCapture, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: const CaptureScreen())),
          GoRoute(path: Routes.workerHazard, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: const HazardReportScreen())),
          GoRoute(
            path: Routes.workerSos,
            // A real SOS is only sent when the button opened this page (extra == true). A reload, back/forward or typed link never sends one.
            redirect: (c, s) => s.uri.queryParameters['mode'] == 'evac' || s.extra == true ? null : Routes.worker,
            pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: SosScreen(evacOnly: s.uri.queryParameters['mode'] == 'evac'))),
          GoRoute(path: Routes.supervisor, pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const SupervisorHomeScreen())),
          GoRoute(path: Routes.supervisorHazard, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: HazardDetailScreen(hazardId: s.pathParameters['hazardId']!, initial: s.extra is HazardFeed ? s.extra as HazardFeed : null))),
          GoRoute(path: Routes.admin, pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const AdminHomeScreen())),
          if (kDebugMode) GoRoute(path: Routes.devUi, builder: (c, s) => const UiGalleryScreen()),
          ...phase2Routes(),
          ...extraRoutes,
        ],
      ),
    ],
  );
}
