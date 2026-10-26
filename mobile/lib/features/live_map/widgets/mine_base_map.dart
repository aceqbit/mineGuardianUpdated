import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme/tokens.dart';
import '../../../contracts/enums.dart';
import '../../../core/maps/google_tiles.dart';
import '../../../core/models/mine_layout.dart';
import '../data/route_modes.dart';

LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

/// Colour of each route mode on the map and in its card.
Color modeColor(MgColors c, RouteMode m) => switch (m) {
      RouteMode.leastHindrance => c.success,
      RouteMode.mostLight => c.amber500,
      RouteMode.mostAid => c.info,
      RouteMode.direct => c.text,
    };

IconData aidIcon(String aidType) {
  try {
    return AidType.fromWire(aidType).icon;
  } catch (_) {
    return Icons.place;
  }
}

/// The real mine on a real base map (CLAUDE.md section 23.4): Google Map Tiles when GOOGLE_MAPS_API_KEY is set, the
/// layout (tunnels coloured by airway, unlit spans dashed, blocked tunnels red), exits, refuges, aid points and live
/// hazards. Without a key it says so and draws the real layout on a plain background — never invented geometry.
class MineBaseMap extends StatefulWidget {
  const MineBaseMap({super.key, required this.layout, this.controller, this.hazards = const [], this.layers = const [], this.markers = const [], this.onLongPress, this.onTapTarget, this.fitPoints = const [], this.highlightTargetId});
  final MineLayoutData layout;
  final MapController? controller;
  final List<RouteHazard> hazards;

  /// Extra layers drawn above the layout and below the markers (routes, trails).
  final List<Widget> layers;
  final List<Marker> markers;
  final ValueChanged<GeoPoint>? onLongPress;
  final ValueChanged<String>? onTapTarget;

  /// Points the first camera fit should include (defaults to the whole layout).
  final List<GeoPoint> fitPoints;
  final String? highlightTargetId;

  @override
  State<MineBaseMap> createState() => _MineBaseMapState();
}

class _MineBaseMapState extends State<MineBaseMap> {
  String? _tiles;
  bool _tilesChecked = false;

  @override
  void initState() {
    super.initState();
    GoogleTiles.instance.template().then((t) {
      if (mounted) {
        setState(() {
          _tiles = t;
          _tilesChecked = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final l = widget.layout;
    final fit = [...widget.fitPoints, for (final j in l.junctions) j.point];
    final bounds = fit.length < 2 ? null : LatLngBounds.fromPoints(fit.map(toLatLng).toList());
    final lines = <Polyline>[
      for (final t in l.tunnels)
        Polyline(
          points: t.coords.map(toLatLng).toList(),
          strokeWidth: t.widthM >= 3 ? 5 : 3.5,
          color: (t.blocked ? c.danger : (t.airway == 'intake' ? c.info : c.slate500)).withValues(alpha: 0.75),
          pattern: t.blocked || (t.lightLux ?? 0) < litLux ? StrokePattern.dashed(segments: const [7, 6]) : const StrokePattern.solid(),
        ),
    ];
    Marker poi(GeoPoint p, String id, IconData icon, Color color, String label, {double size = 26}) => Marker(
          point: toLatLng(p),
          width: size + 10,
          height: size + 10,
          child: Semantics(
            button: widget.onTapTarget != null,
            label: label,
            child: GestureDetector(
              onTap: widget.onTapTarget == null ? null : () => widget.onTapTarget!(id),
              child: Container(
                decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: id == widget.highlightTargetId ? c.amber500 : color, width: id == widget.highlightTargetId ? 3 : 1.5), boxShadow: Shadows.level(1)),
                child: Icon(icon, size: size * 0.62, color: color),
              ),
            ),
          ),
        );
    return Stack(children: [
      Positioned.fill(
        child: FlutterMap(
          mapController: widget.controller,
          options: MapOptions(
            backgroundColor: c.slate100,
            initialCenter: toLatLng(l.anchor),
            initialZoom: 17,
            minZoom: 14,
            maxZoom: 20,
            initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(40, 140, 40, 200), maxZoom: 19),
            onLongPress: widget.onLongPress == null ? null : (_, ll) => widget.onLongPress!(GeoPoint(ll.latitude, ll.longitude)),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            if (_tiles != null)
              TileLayer(urlTemplate: _tiles!, userAgentPackageName: 'app.mineguardian.mobile', maxNativeZoom: 19, errorTileCallback: (tile, error, stack) {}),
            PolylineLayer(polylines: lines),
            ...widget.layers,
            MarkerLayer(markers: [
              for (final a in l.aids) poi(a.point, a.id, aidIcon(a.aidType), c.info, a.name, size: 22),
              for (final r in l.refuges) poi(r.point, r.id, Icons.home_work, c.info, r.name),
              for (final x in l.exits) poi(x.point, x.id, Icons.exit_to_app, c.success, x.name, size: 30),
              for (final h in widget.hazards)
                Marker(point: toLatLng(h.point), width: 32, height: 32, child: Semantics(label: 'Hazard ${h.category}', child: Icon(Icons.warning_rounded, size: 28, color: h.closesTunnels ? c.danger : c.warning))),
              ...widget.markers,
            ]),
          ],
        ),
      ),
      if (_tilesChecked && _tiles == null)
        Positioned(
          left: Space.md,
          bottom: Space.md,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            decoration: BoxDecoration(color: c.surface.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: c.border)),
            child: Text('Base map off: set GOOGLE_MAPS_API_KEY · real mine layout shown', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.muted)),
          ),
        ),
      if (_tiles != null) Positioned(left: 6, bottom: 2, child: Text('Map data © Google', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9, color: c.ink900))),
    ]);
  }
}
