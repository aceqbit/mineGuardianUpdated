import '../../../core/api/api_client.dart';
import 'profile_models.dart';

class ProfilePage {
  const ProfilePage({required this.items, required this.total});
  final List<ProfileCard> items;
  final int total;
}

/// GET/PATCH /api/profiles (CLAUDE.md section 23.2). The server trims every answer to what the viewer may see.
class ProfilesRepository {
  ProfilesRepository({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<ProfilePage> list({String? role, String? zoneId, String? q}) async {
    final j = await _api.getJson('/api/profiles', query: {'limit': 200, 'role': ?role, 'zoneId': ?zoneId, if (q != null && q.trim().isNotEmpty) 'q': q.trim()});
    final items = ((j['items'] as List?) ?? const []).map((e) => ProfileCard.fromJson((e as Map).cast<String, dynamic>())).toList();
    return ProfilePage(items: items, total: (j['total'] as num?)?.toInt() ?? items.length);
  }

  Future<ProfileDetail> detail(String userId) async => ProfileDetail.fromJson(((await _api.getJson('/api/profiles/$userId'))['profile'] as Map).cast<String, dynamic>());

  /// Only the changed keys; null clears a field.
  Future<ProfileDetail> patch(String userId, Map<String, dynamic> changes) async =>
      ProfileDetail.fromJson(((await _api.patchJson('/api/profiles/$userId', body: changes))['profile'] as Map).cast<String, dynamic>());
}
