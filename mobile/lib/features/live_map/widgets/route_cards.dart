import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/glass_card.dart';
import '../../../app/ui/mg_text_field.dart';
import '../../../contracts/enums.dart';
import '../data/route_modes.dart';
import 'mine_base_map.dart';

String fmtDistance(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
String fmtEta(double sec) => sec < 60 ? '${sec.round()} s' : '${(sec / 60).ceil()} min';

/// One route option (CLAUDE.md section 23.4): the modes that chose it, distance, ETA, % lit, aid points, hazards near.
class RouteCard extends StatelessWidget {
  const RouteCard({super.key, required this.route, required this.selected, required this.onTap, this.speedMps, this.width});
  final ModeRoute route;
  final bool selected;
  final VoidCallback onTap;
  final double? speedMps;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final color = modeColor(c, route.primary);
    final compact = width != null;
    Widget modeChip(RouteMode m) => Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
          decoration: BoxDecoration(color: modeColor(c, m).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: modeColor(c, m).withValues(alpha: 0.6))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.icon, size: 13, color: c.text), const SizedBox(width: 4), Flexible(child: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: c.text, fontWeight: FontWeight.w700)))]),
        );
    final modes = RouteMode.values.where(route.modes.contains).toList();
    final facts = [
      _Fact(icon: Icons.light_mode, text: '${(route.litPct * 100).round()}% lit'),
      _Fact(icon: Icons.medical_services, text: '${route.aidsPassed.length} aid'),
      _Fact(icon: Icons.warning_amber, text: route.hazardsNear == 0 ? 'clear' : '${route.hazardsNear} near hazard', warn: route.hazardsNear > 0),
    ];
    if (compact) {
      // Fixed-height strip on phones: one chip (+N), one line per fact group, nothing wraps.
      return SizedBox(
        width: width,
        child: GlassCard(
          onTap: onTap,
          accent: selected ? color : null,
          padding: const EdgeInsets.all(Space.md),
          semanticLabel: '${route.modes.map((m) => m.label).join(' and ')} route, ${fmtDistance(route.distanceM)}, ${fmtEta(route.etaSec(speedMps))}${selected ? ', selected' : ''}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: modeChip(modes.first)),
              if (modes.length > 1) ...[const SizedBox(width: Space.xs), Text('+${modes.length - 1}', style: t.labelSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w700))],
            ]),
            const SizedBox(height: Space.sm),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtEta(route.etaSec(speedMps)), style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: Space.sm),
              Flexible(child: Text(fmtDistance(route.distanceM), style: t.bodyMedium?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: Space.xs),
            Text(modes.length > 1 ? modes.map((m) => m.label).join(' · ') : route.primary.hint, style: t.labelMedium?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.xs),
            Row(children: [for (final f in facts) Flexible(child: Padding(padding: const EdgeInsets.only(right: Space.sm), child: f))]),
          ]),
        ),
      );
    }
    final card = GlassCard(
      onTap: onTap,
      accent: selected ? color : null,
      padding: const EdgeInsets.all(Space.md),
      semanticLabel: '${route.modes.map((m) => m.label).join(' and ')} route, ${fmtDistance(route.distanceM)}, ${fmtEta(route.etaSec(speedMps))}${selected ? ', selected' : ''}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [for (final m in modes) modeChip(m)]),
        const SizedBox(height: Space.sm),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtEta(route.etaSec(speedMps)), style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: Space.sm),
          Flexible(child: Text(fmtDistance(route.distanceM), style: t.bodyMedium?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: Space.xs),
        Text(route.primary.hint, style: t.labelMedium?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.md, runSpacing: Space.xs, children: facts),
      ]),
    );
    return card;
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.warn = false});
  final IconData icon;
  final String text;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final color = warn ? c.warning : c.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)))]);
  }
}

/// Destination picker: exits and refuges first, then aid points, then junctions; searchable.
Future<String?> showDestinationPicker(BuildContext context, {required List<RouteTarget> targets, String? currentId}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DestinationSheet(targets: targets, currentId: currentId),
  );
}

class _DestinationSheet extends StatefulWidget {
  const _DestinationSheet({required this.targets, this.currentId});
  final List<RouteTarget> targets;
  final String? currentId;
  @override
  State<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends State<_DestinationSheet> {
  late final TextEditingController _q;
  @override
  void initState() {
    super.initState();
    _q = TextEditingController();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final q = _q.text.trim().toLowerCase();
    final list = widget.targets.where((x) => q.isEmpty || x.name.toLowerCase().contains(q) || x.id.toLowerCase().contains(q)).toList();
    IconData icon(RouteTarget x) => switch (x.kind) { TargetKind.exit => Icons.exit_to_app, TargetKind.refuge => Icons.home_work, TargetKind.aid => aidIcon(x.aidType ?? ''), TargetKind.junction => Icons.radio_button_checked };
    String group(TargetKind k) => switch (k) { TargetKind.exit => 'Exits', TargetKind.refuge => 'Refuge chambers', TargetKind.aid => 'Aid points', TargetKind.junction => 'Junctions' };
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: MgTextField(controller: _q, hint: 'Search exits, refuges, aid points, junctions', prefix: const Icon(Icons.search), onChanged: (_) => setState(() {})),
          ),
          Expanded(
            child: ListView(children: [
              for (final k in TargetKind.values)
                if (list.any((x) => x.kind == k)) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xs), child: Text(group(k), style: t.labelLarge?.copyWith(color: c.muted))),
                  for (final x in list.where((x) => x.kind == k))
                    ListTile(
                      leading: Icon(icon(x), color: x.kind == TargetKind.exit ? c.success : c.info),
                      title: Text(x.name),
                      subtitle: x.kind == TargetKind.junction ? null : Text('at ${x.node}'),
                      trailing: x.id == widget.currentId ? Icon(Icons.check_circle, color: c.amberText) : null,
                      onTap: () => Navigator.of(context).pop(x.id),
                    ),
                ],
            ]),
          ),
        ]),
      ),
    );
  }
}
