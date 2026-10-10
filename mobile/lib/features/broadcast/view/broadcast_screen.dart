import 'dart:async';

import 'package:flutter/material.dart';
import '../../../app/ui/skeleton.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/status_chip.dart';
import '../../../app/ui/toast.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/time/ist.dart';
import '../../admin_home/data/admin_repository.dart';
import '../../admin_home/widgets/admin_nav.dart';
import '../data/broadcast_repository.dart';

class BroadcastState {
  const BroadcastState({this.loading = true, this.sending = false, this.sent = const [], this.replies = const [], this.zones = const [], this.error});
  final bool loading, sending;
  final List<BroadcastMsg> sent;
  final List<BroadcastReplyMsg> replies;
  final List<ZoneOverview> zones;
  final String? error;
  BroadcastState copyWith({bool? loading, bool? sending, List<BroadcastMsg>? sent, List<BroadcastReplyMsg>? replies, List<ZoneOverview>? zones, String? error, bool clearError = false}) =>
      BroadcastState(loading: loading ?? this.loading, sending: sending ?? this.sending, sent: sent ?? this.sent, replies: replies ?? this.replies, zones: zones ?? this.zones, error: clearError ? null : (error ?? this.error));
}

/// Composer + sent list with live delivered/read counters + reply inbox. Counters and replies update from broadcast:stats / broadcast:reply.
class BroadcastCubit extends Cubit<BroadcastState> {
  BroadcastCubit(this._repo, SocketService socket, this._zones) : super(const BroadcastState()) {
    _subs.add(socket.on(SocketEvents.broadcastStats).listen((env) {
      final d = env.data;
      emit(state.copyWith(sent: [for (final m in state.sent) m.id == d['broadcastId'].toString() ? m.withStats(targets: (d['targets'] as num?)?.toInt(), delivered: (d['delivered'] as num?)?.toInt(), read: (d['read'] as num?)?.toInt()) : m]));
    }));
    _subs.add(socket.on(SocketEvents.broadcastReply).listen((env) {
      final r = BroadcastReplyMsg.fromJson(env.data);
      emit(state.copyWith(replies: [r, ...state.replies.where((x) => x.id != r.id)]));
    }));
    _subs.add(socket.on(SocketEvents.broadcastMessage).listen((_) => unawaited(_refreshSent())));
  }
  final BroadcastRepository _repo;
  final Future<List<ZoneOverview>> Function() _zones;
  final _subs = <StreamSubscription<dynamic>>[];

  Future<void> _refreshSent() async {
    try {
      emit(state.copyWith(sent: await _repo.history()));
    } on ApiException {
      // keep what we have
    }
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([_repo.history(), _repo.replies(), _zones()]);
      emit(BroadcastState(loading: false, sent: r[0] as List<BroadcastMsg>, replies: r[1] as List<BroadcastReplyMsg>, zones: r[2] as List<ZoneOverview>));
    } on ApiException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    }
  }

  Future<String?> send({required String text, required BroadcastPriority priority, required BroadcastScope scope, String? zoneId, String? role}) async {
    emit(state.copyWith(sending: true, clearError: true));
    try {
      await _repo.send(text: text, priority: priority, scope: scope, zoneId: zoneId, role: role);
      emit(state.copyWith(sending: false));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _refreshSent();
      return null;
    } on ApiException catch (e) {
      emit(state.copyWith(sending: false));
      return e.message;
    }
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}

class BroadcastScreen extends StatelessWidget {
  const BroadcastScreen({super.key, this.repository, this.zones});
  final BroadcastRepository? repository;
  final List<ZoneOverview>? zones;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => BroadcastCubit(repository ?? BroadcastRepository(api: ctx.read<ApiClient>()), ctx.read<SocketService>(), () async => zones ?? (await AdminRepository(api: ctx.read<ApiClient>()).overview()).zones)..load(),
        child: AdminScaffold(section: AdminSection.broadcast, title: 'Broadcast', body: const _Body()),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _text = TextEditingController();
  BroadcastPriority _priority = BroadcastPriority.info;
  BroadcastScope _scope = BroadcastScope.all;
  String? _zoneId;
  Role _role = Role.miner;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().isNotEmpty && _text.text.trim().length <= 280 && (_scope != BroadcastScope.zone || _zoneId != null);

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return BlocBuilder<BroadcastCubit, BroadcastState>(
      builder: (context, s) {
        final composer = MgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('New broadcast', style: t.titleSmall),
            const SizedBox(height: Space.md),
            TextField(key: const ValueKey('bc-text'), controller: _text, maxLines: 3, maxLength: 280, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Message to send')),
            SegmentedButton<BroadcastPriority>(
              showSelectedIcon: false,
              segments: [for (final p in BroadcastPriority.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_priority},
              onSelectionChanged: (v) => setState(() => _priority = v.first),
            ),
            const SizedBox(height: Space.md),
            SegmentedButton<BroadcastScope>(
              showSelectedIcon: false,
              segments: [for (final p in BroadcastScope.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_scope},
              onSelectionChanged: (v) => setState(() => _scope = v.first),
            ),
            if (_scope == BroadcastScope.zone)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: DropdownButtonFormField<String>(
                  initialValue: _zoneId,
                  decoration: const InputDecoration(labelText: 'Zone'),
                  items: [for (final z in s.zones) DropdownMenuItem(value: z.id, child: Text('${z.code} · ${z.name}'))],
                  onChanged: (v) => setState(() => _zoneId = v),
                ),
              ),
            if (_scope == BroadcastScope.role)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: DropdownButtonFormField<Role>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [for (final r in Role.values) DropdownMenuItem(value: r, child: Text(r.wire))],
                  onChanged: (v) => setState(() => _role = v ?? Role.miner),
                ),
              ),
            if (_priority == BroadcastPriority.emergency)
              Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('Emergency messages also go by SMS to people who are offline (up to 20).', style: t.bodySmall?.copyWith(color: c.danger))),
            const SizedBox(height: Space.md),
            MgButton(
              label: 'Send',
              icon: Icons.send,
              expand: true,
              loading: s.sending,
              kind: _priority == BroadcastPriority.emergency ? MgButtonKind.danger : MgButtonKind.primary,
              onPressed: !_valid ? null : () async {
                final cubit = context.read<BroadcastCubit>();
                final err = await cubit.send(text: _text.text, priority: _priority, scope: _scope, zoneId: _zoneId, role: _scope == BroadcastScope.role ? _role.wire : null);
                if (!context.mounted) return;
                if (err == null) {
                  _text.clear();
                  setState(() {});
                }
                Toast.show(context, err ?? 'Broadcast sent', kind: err == null ? ToastKind.success : ToastKind.error);
              },
            ),
          ]),
        );
        final sent = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader(title: 'Sent'),
          if (s.sent.isEmpty) const EmptyState(icon: Icons.campaign, title: 'Nothing sent yet'),
          for (final m in s.sent)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: MgCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusChip(label: m.priority.label, tone: switch (m.priority) { BroadcastPriority.emergency => ChipTone.crisis, BroadcastPriority.urgent => ChipTone.warning, BroadcastPriority.info => ChipTone.neutral }),
                    const SizedBox(width: Space.sm),
                    if (m.createdAt != null) Text(formatIst(m.createdAt!, pattern: 'dd MMM HH:mm'), style: t.bodySmall?.copyWith(color: c.muted)),
                  ]),
                  const SizedBox(height: Space.xs),
                  Text(m.text, style: t.bodyMedium),
                  const SizedBox(height: Space.xs),
                  Text('Delivered ${m.delivered}/${m.targets} · Read ${m.read} · Replies ${m.replies}', key: ValueKey('stats-${m.id}'), style: t.bodySmall?.copyWith(color: c.muted)),
                ]),
              ),
            ),
        ]);
        final inbox = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader(title: 'Replies'),
          if (s.replies.isEmpty) const EmptyState(icon: Icons.forum, title: 'No replies yet'),
          for (final r in s.replies.take(30))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: MgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.userName, style: t.titleSmall), Text(r.text, style: t.bodyMedium), if (r.at != null) Text(formatIst(r.at!, pattern: 'dd MMM HH:mm'), style: t.bodySmall?.copyWith(color: c.muted))])),
            ),
        ]);
        if (s.loading) return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 4));
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Space.lg),
          child: ContentWidth(
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth >= 900) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: composer),
                  const SizedBox(width: Space.lg),
                  Expanded(flex: 5, child: Column(children: [sent, inbox])),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [composer, sent, inbox]);
            }),
          ),
        );
      },
    );
  }
}
