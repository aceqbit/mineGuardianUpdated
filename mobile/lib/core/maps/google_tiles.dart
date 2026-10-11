import 'package:dio/dio.dart';

import '../../config.dart';

/// Base-map tiles from Google's Map Tiles API for the flutter_map evacuation map.
/// A session is created once with the app's API key, then every tile URL carries that session. No key (or no network)
/// means [template] returns null and the map simply has no base tiles; the mine layout is drawn on top regardless.
class GoogleTiles {
  GoogleTiles({Dio? dio, String? apiKey}) : _dio = dio ?? Dio(), _key = apiKey ?? googleMapsApiKey;

  static final GoogleTiles instance = GoogleTiles();

  final Dio _dio;
  final String _key;
  String? _template;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  bool get enabled => _key.isNotEmpty;

  /// flutter_map `urlTemplate` (with {z}/{x}/{y}), or null when Google tiles are not available.
  Future<String?> template() async {
    if (!enabled) return null;
    if (_template != null && DateTime.now().isBefore(_expires)) return _template;
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        'https://tile.googleapis.com/v1/createSession',
        queryParameters: {'key': _key},
        data: {'mapType': 'roadmap', 'language': 'en-IN', 'region': 'IN'},
        options: Options(sendTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)),
      );
      final session = r.data?['session'] as String?;
      if (session == null) return null;
      final expirySec = int.tryParse('${r.data?['expiry']}');
      // Renew a day early; fall back to an hour when the response carries no expiry.
      _expires = expirySec == null ? DateTime.now().add(const Duration(hours: 1)) : DateTime.fromMillisecondsSinceEpoch(expirySec * 1000).subtract(const Duration(days: 1));
      return _template = 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=$session&key=$_key';
    } catch (_) {
      return null;
    }
  }
}
