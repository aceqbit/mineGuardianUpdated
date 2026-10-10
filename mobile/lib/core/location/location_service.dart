import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationFix {
  const LocationFix({required this.lat, required this.lng, required this.accuracyM, required this.ts, this.isFallback = false, this.headingDeg, this.speedMps});
  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime ts;

  /// Direction of travel in degrees from north (null when stationary or unknown).
  final double? headingDeg;
  final double? speedMps;

  /// True when the fix came from the last known position rather than a fresh reading.
  final bool isFallback;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'accuracyM': accuracyM, 'ts': ts.toUtc().toIso8601String(), 'isFallback': isFallback};
}

enum LocationAccess { granted, denied, deniedForever, serviceOff }

class LocationService {
  /// Clear permission flow. Returns the resulting access level; never throws.
  Future<LocationAccess> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) return LocationAccess.deniedForever;
      if (p == LocationPermission.denied) return LocationAccess.denied;
      return LocationAccess.granted;
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  /// High-accuracy fix with a 10 s limit, falling back to the last known position. Null when unavailable.
  Future<LocationFix?> getCurrent() async {
    if (await ensurePermission() != LocationAccess.granted) return lastKnown();
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      return _fix(p, false);
    } catch (_) {
      return lastKnown();
    }
  }

  Future<LocationFix?> lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : _fix(p, true);
    } catch (_) {
      return null;
    }
  }

  /// Continuous stream (used while an SOS is active).
  Stream<LocationFix> stream({int distanceFilter = 5}) => Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilter)).map((p) => _fix(p, false));

  LocationFix _fix(Position p, bool fallback) => LocationFix(
        lat: p.latitude,
        lng: p.longitude,
        accuracyM: p.accuracy,
        ts: p.timestamp.toUtc(),
        isFallback: fallback,
        headingDeg: !fallback && p.heading >= 0 && p.speed > 0.5 ? p.heading : null,
        speedMps: fallback ? null : p.speed,
      );
}
