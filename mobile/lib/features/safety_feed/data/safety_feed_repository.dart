import 'package:equatable/equatable.dart';

import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/cache_repository.dart';

class FeedSource extends Equatable {
  const FeedSource({required this.domain, required this.title, this.url});
  final String domain, title;
  final String? url;
  @override
  List<Object?> get props => [domain, url];
}

class SafetyItem extends Equatable {
  const SafetyItem({required this.id, required this.kind, required this.title, required this.body, this.steps = const [], this.hazardCategory, this.sources = const []});
  final String id;
  final SafetyItemKind kind;
  final String title, body;
  final List<String> steps;
  final String? hazardCategory;
  final List<FeedSource> sources;

  static SafetyItem? fromJson(Map<String, dynamic> j) {
    try {
      return SafetyItem(
        id: '${j['id']}',
        kind: SafetyItemKind.fromWire('${j['kind']}'),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        steps: ((j['steps'] as List?) ?? const []).map((s) => '$s').toList(),
        hazardCategory: j['hazardCategory'] as String?,
        sources: ((j['sources'] as List?) ?? const []).map((s) => FeedSource(domain: '${(s as Map)['domain']}', title: '${s['title'] ?? ''}', url: s['url'] as String?)).toList(),
      );
    } catch (_) {
      return null; // unknown kind from a newer server: skip it
    }
  }

  @override
  List<Object?> get props => [id, kind, title];
}

class FeedVideo extends Equatable {
  const FeedVideo({required this.kind, required this.itemId, required this.title, this.frames = const [], this.url});
  final String kind; // storyboard | veo
  final String itemId, title;
  final List<String> frames;
  final String? url;
  bool get isVeo => kind == 'veo';
  @override
  List<Object?> get props => [kind, itemId, url];
}

class SafetyFeed extends Equatable {
  const SafetyFeed({required this.date, required this.version, required this.items, required this.videos, this.generatedAt});
  final String date;
  final int version;
  final List<SafetyItem> items;
  final List<FeedVideo> videos;
  final DateTime? generatedAt;

  List<SafetyItem> of(SafetyItemKind k) => items.where((i) => i.kind == k).toList();

  factory SafetyFeed.fromJson(Map<String, dynamic> j) => SafetyFeed(
        date: '${j['date']}',
        version: (j['version'] as num?)?.toInt() ?? 1,
        generatedAt: DateTime.tryParse('${j['generatedAt']}'),
        items: ((j['items'] as List?) ?? const []).map((e) => SafetyItem.fromJson((e as Map).cast<String, dynamic>())).whereType<SafetyItem>().toList(),
        videos: ((j['videos'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .map((v) => FeedVideo(kind: '${v['kind']}', itemId: '${v['itemId']}', title: '${v['title'] ?? ''}', frames: ((v['frames'] as List?) ?? const []).map((f) => '$f').toList(), url: v['url'] as String?))
            .where((v) => v.kind == 'storyboard' || (v.kind == 'veo' && v.url != null))
            .toList(),
      );

  @override
  List<Object?> get props => [date, version];
}

enum FeedAvailability { live, cached, notConfigured, notReady, offline }

class FeedResult {
  const FeedResult({required this.availability, this.feed});
  final FeedAvailability availability;
  final SafetyFeed? feed;
}

/// GET /api/safety-feed/today, cached in cache_kv('safety_feed') so the bar works offline (CLAUDE.md section 23.6).
class SafetyFeedRepository {
  SafetyFeedRepository({required ApiClient api, required CacheRepository cache})
      : _api = api,
        _cache = cache;
  final ApiClient _api;
  final CacheRepository _cache;
  static const cacheKey = 'safety_feed';

  Future<SafetyFeed?> cached() async {
    final raw = await _cache.read(cacheKey);
    return raw is Map ? SafetyFeed.fromJson(raw.cast<String, dynamic>()) : null;
  }

  Future<FeedResult> today() async {
    try {
      final j = await _api.getJson('/api/safety-feed/today');
      final raw = (j['feed'] as Map).cast<String, dynamic>();
      await _cache.write(cacheKey, raw);
      return FeedResult(availability: FeedAvailability.live, feed: SafetyFeed.fromJson(raw));
    } on ApiException catch (e) {
      final old = await cached();
      final why = switch (e.code) { 'FEED_NOT_CONFIGURED' => FeedAvailability.notConfigured, 'FEED_NOT_READY' => FeedAvailability.notReady, _ => FeedAvailability.offline };
      return FeedResult(availability: old != null && why == FeedAvailability.offline ? FeedAvailability.cached : why, feed: old);
    }
  }
}
