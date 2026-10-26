/// Contract v1 Flutter routes.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const worker = '/worker';
  static const workerCapture = '/worker/capture';
  static const workerHazard = '/worker/hazard';
  static const workerSos = '/worker/sos';
  static const supervisor = '/supervisor';
  static const supervisorHazard = '/supervisor/hazard/:hazardId';
  static const supervisorReview = '/supervisor/review/:checkInId';
  static const admin = '/admin';
  static const adminNormal = '/admin/normal';
  static const adminReports = '/admin/reports';
  static const adminCrisis = '/admin/crisis';
  static const adminBroadcast = '/admin/broadcast';
  static const adminContacts = '/admin/contacts';
  static const leaderboard = '/leaderboard';
  static const rewards = '/rewards';
  static const crisisView = '/crisis/view';
  static const devUi = '/dev/ui';

  // add-on pack X (lib/addons/addon_routes.dart)
  static const workerProfiles = '/worker/profiles';
  static const supervisorProfiles = '/supervisor/profiles';
  static const adminProfiles = '/admin/profiles';
  static const profileDetail = '/profiles/:userId';
  static const workerMap = '/worker/map';
  static const supervisorLiveMap = '/supervisor/live-map';
  static const adminLiveMap = '/admin/live-map';
  static const workerSafety = '/worker/safety';

  static String profile(String userId) => '/profiles/$userId';
  static String profilesFor(String role) => switch (role) { 'supervisor' => supervisorProfiles, 'admin' => adminProfiles, _ => workerProfiles };
  static String liveMapFor(String role) => switch (role) { 'supervisor' => supervisorLiveMap, 'admin' => adminLiveMap, _ => workerMap };

  static String review(String checkInId) => '/supervisor/review/$checkInId';
  static String hazardDetail(String hazardId) => '/supervisor/hazard/$hazardId';
  static const workerSosEvac = '/worker/sos?mode=evac';

  /// Home route for a role wire string.
  static String homeFor(String role) {
    switch (role) {
      case 'supervisor':
        return supervisor;
      case 'admin':
        return admin;
      default:
        return worker;
    }
  }
}
