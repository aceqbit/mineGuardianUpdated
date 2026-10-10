import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/tokens.dart';
import '../bloc/sos_bloc.dart';
import '../bloc/sos_event.dart';
import '../bloc/sos_state.dart';
import 'evac_map_view.dart';
import 'live_nav_map.dart';

/// Live map (default) or the tile-less schematic. The schematic stays available because it is the proven
/// zero-connectivity view; the live map also works offline (without base tiles) once the layout is cached.
class SosMapPanel extends StatefulWidget {
  const SosMapPanel({super.key, required this.state});
  final SosState state;

  @override
  State<SosMapPanel> createState() => _SosMapPanelState();
}

class _SosMapPanelState extends State<SosMapPanel> {
  bool _schematic = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = MgColors.of(context);
    if (s.layout == null) return EvacMapView(state: s); // shows the "map not downloaded" message
    return Stack(children: [
      Positioned.fill(
        child: _schematic ? EvacMapView(state: s) : LiveNavMap(state: s, onSelectRoute: (id) => context.read<SosBloc>().add(SosRouteSelected(id))),
      ),
      Positioned(
        right: _schematic ? Space.md : null,
        left: _schematic ? null : Space.md,
        top: _schematic ? 64 + Space.sm : null,
        bottom: _schematic ? null : (s.alternatives.length > 1 && s.activeControlRoute == null ? 72 : 28),
        child: Material(
          color: c.surface,
          shape: const StadiumBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _schematic = !_schematic),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_schematic ? Icons.map : Icons.schema, size: 16, color: c.ink900),
                const SizedBox(width: Space.xs),
                Text(_schematic ? 'Live map' : 'Schematic', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.ink900)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
