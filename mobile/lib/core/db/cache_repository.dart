import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Key/value cache used so the SOS screen, evacuation map and first-aid guide work with no connection.
abstract class CacheRepository {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
  Future<void> remove(String key);
}

class CacheKeys {
  CacheKeys._();
  static const layout = 'layout';
  static const profile = 'profile';
  static const zoneSupervisors = 'zone_supervisors';
  static const openHazards = 'open_hazards';
  static const firstAidVersion = 'first_aid_version';
  // add-on X3 live tracking
  static const trackingConsent = 'tracking_consent';
  static const trackingEnabled = 'tracking_enabled';
}

class SqliteCacheRepository implements CacheRepository {
  SqliteCacheRepository(this._db);
  final Database _db;

  @override
  Future<Object?> read(String key) async {
    final rows = await _db.query('cache_kv', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : jsonDecode(rows.first['value_json']! as String);
  }

  @override
  Future<void> write(String key, Object? value) => _db.insert('cache_kv', {'key': key, 'value_json': jsonEncode(value), 'updated_at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> remove(String key) => _db.delete('cache_kv', where: 'key = ?', whereArgs: [key]);
}
