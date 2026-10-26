import 'dart:math' as math;

/// Mine layout GeoJSON (WGS84 [lng, lat]) parsed into plain Dart. Used by the offline evacuation map and zone detection.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  static GeoPoint fromCoord(List<dynamic> c) => GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble());
}

double haversineM(GeoPoint a, GeoPoint b) {
  const r = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final s = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(s)));
}

/// Ray casting on a ring of points.
bool pointInRing(GeoPoint p, List<GeoPoint> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].lng, yi = ring[i].lat, xj = ring[j].lng, yj = ring[j].lat;
    if ((yi > p.lat) != (yj > p.lat) && p.lng < (xj - xi) * (p.lat - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

class LayoutZone {
  const LayoutZone(this.code, this.ring);
  final String code;
  final List<GeoPoint> ring;
}

class LayoutTunnel {
  const LayoutTunnel({required this.id, required this.from, required this.to, required this.widthM, required this.capacity, required this.slopePct, required this.airway, required this.blocked, required this.coords, this.lightLux});
  final String id;

  /// Add-on X4: measured lighting in lux (null = unknown, treated as unlit by the "most light" route).
  final double? lightLux;
  final String from;
  final String to;
  final double widthM;
  final double capacity;
  final double slopePct;
  final String airway; // intake | return
  final bool blocked;
  final List<GeoPoint> coords;

  double get lengthM {
    var d = 0.0;
    for (var i = 1; i < coords.length; i++) {
      d += haversineM(coords[i - 1], coords[i]);
    }
    return d;
  }
}

class LayoutJunction {
  const LayoutJunction(this.id, this.point);
  final String id;
  final GeoPoint point;
}

class LayoutExit {
  const LayoutExit({required this.id, required this.name, required this.exitType, required this.point, required this.node});
  final String id;
  final String name;
  final String exitType;
  final GeoPoint point;
  final String node;
}

class LayoutRefuge {
  const LayoutRefuge({required this.id, required this.name, required this.capacity, required this.point, required this.node});
  final String id;
  final String name;
  final int capacity;
  final GeoPoint point;
  final String node;
}

/// Add-on X4 aid point (layout `kind: aid`): first aid, tool station, phone, self-rescuer cache, extinguisher.
class LayoutAid {
  const LayoutAid({required this.id, required this.aidType, required this.name, required this.point, required this.node});
  final String id;

  /// AID_TYPE wire value (kept as a string so an unknown future type never breaks parsing).
  final String aidType;
  final String name;
  final GeoPoint point;
  final String node;
}

class MineLayoutData {
  const MineLayoutData({required this.version, required this.anchor, required this.zones, required this.tunnels, required this.junctions, required this.exits, required this.refuges, this.aids = const []});

  /// Add-on X4 aid points (empty for older layouts).
  final List<LayoutAid> aids;
  final int version;
  final GeoPoint anchor;
  final List<LayoutZone> zones;
  final List<LayoutTunnel> tunnels;
  final List<LayoutJunction> junctions;
  final List<LayoutExit> exits;
  final List<LayoutRefuge> refuges;

  /// Parses `{ version, anchor{lat,lng}, geojson: FeatureCollection }` as returned by GET /api/layout.
  factory MineLayoutData.fromJson(Map<String, dynamic> j) {
    final a = j['anchor'] as Map? ?? const {};
    final feats = ((j['geojson'] as Map)['features'] as List).cast<Map>();
    final zones = <LayoutZone>[];
    final tunnels = <LayoutTunnel>[];
    final junctions = <LayoutJunction>[];
    final exits = <LayoutExit>[];
    final refuges = <LayoutRefuge>[];
    final aids = <LayoutAid>[];
    for (final f in feats) {
      final props = (f['properties'] as Map).cast<String, dynamic>();
      final geom = f['geometry'] as Map;
      switch (props['kind']) {
        case 'zone':
          final ring = ((geom['coordinates'] as List).first as List).map((c) => GeoPoint.fromCoord(c as List)).toList();
          zones.add(LayoutZone(props['code'] as String, ring));
        case 'tunnel':
          tunnels.add(LayoutTunnel(
            id: props['id'] as String,
            from: props['fromNode'] as String,
            to: props['toNode'] as String,
            widthM: (props['widthM'] as num).toDouble(),
            capacity: (props['capacity'] as num).toDouble(),
            slopePct: (props['slopePct'] as num).toDouble(),
            airway: props['airway'] as String,
            blocked: props['status'] == 'blocked',
            coords: (geom['coordinates'] as List).map((c) => GeoPoint.fromCoord(c as List)).toList(),
            lightLux: (props['lightLux'] as num?)?.toDouble(),
          ));
        case 'junction':
          junctions.add(LayoutJunction(props['id'] as String, GeoPoint.fromCoord(geom['coordinates'] as List)));
        case 'exit':
          exits.add(LayoutExit(id: props['id'] as String, name: props['name'] as String? ?? '', exitType: props['exitType'] as String? ?? 'shaft', point: GeoPoint.fromCoord(geom['coordinates'] as List), node: props['node'] as String? ?? ''));
        case 'aid':
          aids.add(LayoutAid(id: props['id'] as String, aidType: props['aidType'] as String? ?? 'FIRST_AID', name: props['name'] as String? ?? '', point: GeoPoint.fromCoord(geom['coordinates'] as List), node: props['node'] as String? ?? ''));
        case 'refuge':
          refuges.add(LayoutRefuge(id: props['id'] as String, name: props['name'] as String? ?? '', capacity: (props['capacity'] as num?)?.toInt() ?? 0, point: GeoPoint.fromCoord(geom['coordinates'] as List), node: props['node'] as String? ?? ''));
      }
    }
    return MineLayoutData(
      version: (j['version'] as num?)?.toInt() ?? 1,
      anchor: GeoPoint((a['lat'] as num?)?.toDouble() ?? 0, (a['lng'] as num?)?.toDouble() ?? 0),
      zones: zones,
      tunnels: tunnels,
      junctions: junctions,
      exits: exits,
      refuges: refuges,
      aids: aids,
    );
  }

  /// Zone code containing the point, or null.
  String? zoneCodeAt(double lat, double lng) {
    final p = GeoPoint(lat, lng);
    for (final z in zones) {
      if (pointInRing(p, z.ring)) return z.code;
    }
    return null;
  }

  /// Local metres (x east, y north) relative to the layout anchor.
  ({double x, double y}) toLocal(GeoPoint p) => (
        x: (p.lng - anchor.lng) * 111320 * math.cos(anchor.lat * math.pi / 180),
        y: (p.lat - anchor.lat) * 111320,
      );
}
