import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../bloc/sos_state.dart';

/// Bottom sheet to fix the two ends of the route: where it starts (live position or a pin) and where it ends (any exit or refuge).
Future<void> showRouteOptions(
  BuildContext context, {
  required SosState state,
  required VoidCallback onUseLiveStart,
  required ValueChanged<String?> onPickDestination,
}) {
  final layout = state.layout;
  if (layout == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      final c = MgColors.of(ctx);
      void pick(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      Widget place(String? id, String name, IconData icon, String sub) => ListTile(
            leading: Icon(icon, color: c.amberText),
            title: Text(name),
            subtitle: Text(sub),
            selected: state.destinationId == id,
            trailing: state.destinationId == id ? const Icon(Icons.check_circle) : null,
            onTap: () => pick(() => onPickDestination(id)),
          );

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg), children: [
            Text('Start', style: t.titleMedium),
            ListTile(
              leading: Icon(Icons.my_location, color: c.amberText),
              title: const Text('My live location'),
              subtitle: const Text('Follows you as you move'),
              selected: state.pinnedStart == null,
              trailing: state.pinnedStart == null ? const Icon(Icons.check_circle) : null,
              onTap: () => pick(onUseLiveStart),
            ),
            ListTile(
              leading: Icon(Icons.push_pin, color: c.amberText),
              title: Text(state.pinnedStart == null ? 'Pin a start on the map' : 'Start pinned on the map'),
              subtitle: const Text('Long-press the map where the route should begin'),
              selected: state.pinnedStart != null,
              trailing: state.pinnedStart != null ? const Icon(Icons.check_circle) : null,
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: Space.md),
            Text('End', style: t.titleMedium),
            place(null, 'Nearest safe exit', Icons.auto_awesome, 'Chosen for you; up to 3 routes, one per exit'),
            for (final e in layout.exits) place(e.id, e.name, Icons.exit_to_app, 'Exit · up to 4 different routes'),
            for (final r in layout.refuges) place(r.id, r.name, Icons.home_work, 'Refuge chamber · up to 4 different routes'),
          ]),
        ),
      );
    },
  );
}
