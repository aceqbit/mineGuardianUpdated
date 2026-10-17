import 'package:go_router/go_router.dart';

import '../app/ui/page_transitions.dart';
import '../contracts/routes.dart';
import '../features/profiles/view/profile_detail_screen.dart';
import '../features/profiles/view/profiles_screen.dart';

/// Add-on pack routes (CLAUDE.md section 23). Role guards come from the path prefix in `sessionRedirect`
/// (/worker*, /supervisor*, /admin*); `/profiles/:userId` is open to every role and scoped by the server.
List<RouteBase> addonRoutes() => [
      GoRoute(path: Routes.workerProfiles, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: const ProfilesScreen())),
      GoRoute(path: Routes.supervisorProfiles, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: const ProfilesScreen())),
      GoRoute(path: Routes.adminProfiles, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: const ProfilesScreen())),
      GoRoute(path: Routes.profileDetail, pageBuilder: (c, s) => sharedAxisPage(key: s.pageKey, child: ProfileDetailScreen(userId: s.pathParameters['userId']!))),
    ];
