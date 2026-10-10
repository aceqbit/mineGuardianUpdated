import 'package:flutter/material.dart';

import '../../core/db/outbox_item.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_status.dart';
import '../../core/time/ist.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';

/// App-bar sync indicator: synced / offline / syncing / failed. Tap opens the queue sheet.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.engine});
  final SyncEngine engine;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: engine.status$,
      initialData: engine.status,
      builder: (context, snap) {
        final s = snap.data ?? engine.status;
        final c = MgColors.of(context);
        late final IconData icon;
        late final Color color;
        late final String label;
        var spin = false;
        if (s.isSyncing) {
          icon = Icons.sync;
          color = c.amberText;
          label = 'Syncing 1 of ${s.pendingCount}';
          spin = true;
        } else if (s.isOffline) {
          icon = Icons.cloud_off;
          color = c.slate500;
          label = s.pendingCount > 0 ? 'Offline · ${s.pendingCount} queued' : 'Offline';
        } else if (s.failedCount > 0) {
          icon = Icons.error_outline;
          color = c.danger;
          label = '${s.failedCount} failed — tap';
        } else if (s.pendingCount > 0) {
          icon = Icons.cloud_upload;
          color = c.amberText;
          label = '${s.pendingCount} queued';
        } else {
          icon = Icons.check_circle;
          color = c.success;
          label = s.lastSyncedAt == null ? 'All synced' : 'All synced · ${formatIst(s.lastSyncedAt!)}';
        }
        final ic = spin && !Motion.reduce(context) ? _Spin(child: Icon(icon, size: 18, color: color)) : Icon(icon, size: 18, color: color);
        return Semantics(
          button: true,
          liveRegion: true,
          label: 'Sync status: $label',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: () => showSyncSheet(context, engine),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ic,
                const SizedBox(width: Space.xs),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color))),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Spin extends StatefulWidget {
  const _Spin({required this.child});
  final Widget child;

  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

IconData _kindIcon(OutboxKind k) => switch (k) {
      OutboxKind.sos => Icons.sos,
      OutboxKind.sosCancel => Icons.cancel,
      OutboxKind.hazard => Icons.warning_amber,
      OutboxKind.checkin => Icons.photo_camera,
      OutboxKind.gps => Icons.my_location,
    };

Future<void> showSyncSheet(BuildContext context, SyncEngine engine) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SyncSheet(engine: engine),
  );
}

class _SyncSheet extends StatefulWidget {
  const _SyncSheet({required this.engine});
  final SyncEngine engine;

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  late Future<List<OutboxItem>> _items = widget.engine.items();

  void _reload() => setState(() => _items = widget.engine.items());

  Future<void> _discard(OutboxItem it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this item?'),
        content: Text('This ${it.kind.label.toLowerCase()} will be deleted and never sent.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard'))],
      ),
    );
    if (ok == true) {
      await widget.engine.discard(it.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sync queue', style: t.headlineSmall),
            const SizedBox(height: Space.md),
            Flexible(
              child: FutureBuilder<List<OutboxItem>>(
                future: _items,
                builder: (context, snap) {
                  final items = snap.data ?? const <OutboxItem>[];
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (items.isEmpty) return Padding(padding: const EdgeInsets.all(Space.x2), child: Center(child: Text('Nothing waiting to sync', style: t.bodyMedium)));
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(color: c.border),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final failed = it.status == OutboxStatus.failed;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_kindIcon(it.kind), color: failed ? c.danger : c.muted),
                        title: Text('${it.kind.label} · ${formatIst(DateTime.fromMillisecondsSinceEpoch(it.createdAt, isUtc: true))}'),
                        subtitle: Text(['${failed ? 'Failed' : 'Waiting'} · ${it.attempts} attempt${it.attempts == 1 ? '' : 's'}', if (it.lastError != null) it.lastError!].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
                        isThreeLine: it.lastError != null,
                        trailing: Wrap(spacing: Space.xs, children: [
                          TextButton(onPressed: () async {
                            await widget.engine.retryNow(it.id);
                            _reload();
                          }, child: const Text('Retry now')),
                          if (it.kind != OutboxKind.sos && it.kind != OutboxKind.sosCancel) TextButton(onPressed: () => _discard(it), child: Text('Discard', style: TextStyle(color: c.danger))),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
