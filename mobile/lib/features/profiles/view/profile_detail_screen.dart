import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/animated_counter.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/glass_card.dart';
import '../../../app/ui/net_photo.dart';
import '../../../app/ui/pulse_on_change.dart';
import '../../../app/ui/role_accent.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/status_chip.dart';
import '../../../app/ui/toast.dart';
import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/time/ist.dart';
import '../../voice_call/widgets/ai_call_button.dart';
import '../bloc/profile_detail_bloc.dart';
import '../data/profile_models.dart';
import '../data/profiles_repository.dart';
import '../widgets/profile_editor_sheet.dart';
import '../widgets/profile_visuals.dart';

const _badgeLabels = {'STREAK_7': '7-day streak', 'STREAK_30': '30-day streak', 'PERFECT_WEEK': 'Perfect week', 'HAZARD_HERO': 'Hazard hero', 'FIRST_PASS_PRO': 'First-pass pro'};

/// One person's profile (route `/profiles/:userId`, or opened from a card). Live: refetches on `profile:updated`.
class ProfileDetailScreen extends StatelessWidget {
  const ProfileDetailScreen({super.key, required this.userId, this.repository, this.initial});
  final String userId;
  final ProfilesRepository? repository;
  final ProfileCard? initial;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionBloc>().state;
    final viewer = session is SessionAuthenticated ? session.user : null;
    return BlocProvider(
      create: (ctx) => ProfileDetailBloc(
        repo: repository ?? ProfilesRepository(api: ctx.read<ApiClient>()),
        socket: ctx.read<SocketService>(),
        userId: userId,
        isSelf: viewer?.id == userId,
      )..add(const ProfileDetailStarted()),
      child: _DetailView(viewerRole: viewer?.role ?? Role.miner, isSelf: viewer?.id == userId, initial: initial),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.viewerRole, required this.isSelf, this.initial});
  final Role viewerRole;
  final bool isSelf;
  final ProfileCard? initial;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileDetailBloc, ProfileDetailState>(
      listenWhen: (a, b) => a.savedAt != b.savedAt || (b.saveError != null && a.saveError != b.saveError),
      listener: (context, s) {
        if (s.saveError != null) {
          Toast.show(context, s.saveError!, kind: ToastKind.error);
        } else {
          Toast.show(context, 'Profile saved', kind: ToastKind.success);
        }
      },
      builder: (context, s) {
        final p = s.profile;
        final canEdit = p != null && (viewerRole == Role.admin || isSelf);
        return Scaffold(
          floatingActionButton: canEdit
              ? FloatingActionButton.extended(
                  onPressed: s.saving
                      ? null
                      : () async {
                          final body = await showProfileEditor(context, profile: p, admin: viewerRole == Role.admin);
                          if (body != null && context.mounted) context.read<ProfileDetailBloc>().add(ProfileSaved(body));
                        },
                  icon: s.saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.edit),
                  label: Text(s.saving ? 'Saving…' : 'Edit'),
                )
              : null,
          body: CustomScrollView(slivers: [
            _Header(profile: p, initial: initial, viewerRole: viewerRole),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.lg, bottom: Space.x4 + Space.x4),
                child: ContentWidth(
                  child: switch (s.status) {
                    DetailStatus.loading => const SkeletonList(count: 4),
                    DetailStatus.failure => EmptyState(icon: Icons.lock_outline, title: 'Profile not available', message: s.error, actionLabel: 'Retry', onAction: () => context.read<ProfileDetailBloc>().add(const ProfileDetailStarted())),
                    DetailStatus.ready => PulseOnChange(pulseKey: s.liveTick == 0 ? null : s.liveTick, radius: Radii.sheet, child: _Sections(p: p!, isSelf: isSelf, viewerRole: viewerRole)),
                  },
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.profile, required this.initial, required this.viewerRole});
  final ProfileDetail? profile;
  final ProfileCard? initial;
  final Role viewerRole;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final name = profile?.fullName ?? initial?.fullName ?? '';
    final role = profile?.role ?? initial?.role ?? Role.miner;
    final photo = profile?.photo?.url ?? initial?.photo?.url;
    final accent = RoleAccent.of(context, role);
    final sub = [profile?.employeeId ?? initial?.employeeId ?? '', role.label, if ((profile?.zone ?? initial?.zone) != null) (profile?.zone ?? initial?.zone)!.code].where((x) => x.isNotEmpty).join(' · ');
    return SliverAppBar(
      pinned: true,
      expandedHeight: 280,
      backgroundColor: c.ink900,
      foregroundColor: Colors.white,
      leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : Navigator.of(context).maybePop()),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: Space.lg, end: Space.lg),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleLarge?.copyWith(color: Colors.white)),
        background: Stack(fit: StackFit.expand, children: [
          if (photo != null) NetPhoto(url: photo, fallbackIcon: Icons.person) else DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(-0.5, -0.6), radius: 1.2, colors: [accent.fill.withValues(alpha: 0.6), c.ink800, c.ink900]))),
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.ink900.withValues(alpha: 0.2), c.ink900.withValues(alpha: 0.92)]))),
          if (photo == null)
            Align(
              alignment: const Alignment(0, -0.15),
              child: ProfileAvatar(name: name, size: 96, ring: accent.fill),
            ),
          Positioned(
            left: 56,
            right: Space.lg,
            bottom: 48,
            child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: c.slate300)),
          ),
        ]),
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.p, required this.isSelf, required this.viewerRole});
  final ProfileDetail p;
  final bool isSelf;
  final Role viewerRole;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final dash = '—';
    final panels = <Widget>[
      if (p.isCrew)
        StatusChip(label: 'Crew view · personal details are private', icon: Icons.lock_outline, tone: ChipTone.info),
      _Panel(title: 'Identity', icon: Icons.badge, children: [
        _Facts(facts: [
          ('Employee ID', p.employeeId),
          ('Role', p.role.label),
          ('Zone', p.zone == null ? dash : '${p.zone!.code} · ${p.zone!.name}'),
          ('Shift', p.shift == null ? dash : '${p.shift!.wire} · ${p.shift!.window} IST'),
          ('Status', p.status == 'active' ? 'Active' : 'Inactive'),
          if (!p.isCrew) ('Designation', p.designation ?? dash),
          if (!p.isCrew) ('Experience', p.experienceYears == null ? dash : '${p.experienceYears} yrs'),
          if (!p.isCrew) ('Joined', p.joinedAt == null ? dash : DateFormat('d MMM y').format(toIst(p.joinedAt!))),
          if (!p.isCrew) ('Email', p.email ?? dash),
          if (!p.isCrew) ('Phone', p.phoneE164 ?? p.phoneMasked ?? dash),
        ]),
      ]),
      // Add-on X5: one tap calls them with the AI voice agent (the server checks scope, number and the emergency blocklist).
      if (!isSelf && (viewerRole != Role.miner || p.role != Role.miner))
        _Panel(title: 'Call', icon: Icons.support_agent, children: [AiCallButton(targetType: 'user', targetId: p.id, targetLabel: p.fullName, expand: true)]),
      if (p.presence != null || !p.isCrew)
        _Panel(title: 'Live location', icon: Icons.my_location, children: [
          if (p.presence == null)
            Text('Not tracked yet', style: t.bodyMedium?.copyWith(color: c.muted))
          else
            Row(children: [
              ProfileAvatar(name: p.fullName, size: 40, presence: p.presence!.presence, photoUrl: p.photo?.url),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  [
                    presenceLabel(p.presence!.presence),
                    if (p.presence!.source != null) switch (p.presence!.source!) { PositionSource.gps => 'GPS', PositionSource.fused => 'GPS + sensors', PositionSource.pdr => 'sensors only' },
                    if (p.presence!.tunnelId != null) p.presence!.tunnelId!,
                    if (p.presence!.accuracyM != null) '±${p.presence!.accuracyM!.round()} m',
                    if (p.presence!.ts != null) relativeTime(p.presence!.ts!),
                  ].join(' · '),
                  style: t.bodyMedium,
                ),
              ),
            ]),
        ]),
      if (p.role == Role.miner && !p.isCrew)
        _Panel(title: 'Compliance', icon: Icons.verified_user, children: [
          Row(children: [
            Text('Today', style: t.labelLarge?.copyWith(color: c.muted)),
            const SizedBox(width: Space.sm),
            StatusChip(label: todayLabel(p.today), tone: todayTone(p.today)),
          ]),
          const SizedBox(height: Space.md),
          if (p.calendar.isEmpty) Text('No check-ins in the last 30 days', style: t.bodyMedium?.copyWith(color: c.muted)) else ComplianceStrip(days: p.calendar),
        ]),
      _Panel(title: 'Safety score', icon: Icons.emoji_events, children: [
        if (p.score == null)
          Text('No score yet — scores appear after reviewed check-ins.', style: t.bodyMedium?.copyWith(color: c.muted))
        else ...[
          Wrap(spacing: Space.x2, runSpacing: Space.md, children: [
            if (p.score!.score != null) _Big(label: 'Score', value: p.score!.score),
            if (p.score!.rank != null) _Big(label: 'Zone rank', value: p.score!.rank, prefix: '#', tail: p.score!.rankOf == null ? null : 'of ${p.score!.rankOf}'),
            _Big(label: 'Streak', value: p.score!.streak, suffix: ' d'),
            _Big(label: 'XP', value: p.score!.xp),
          ]),
          if (p.score!.riskBand != null) ...[
            const SizedBox(height: Space.md),
            Row(children: [Text('Risk band', style: t.labelLarge?.copyWith(color: c.muted)), const SizedBox(width: Space.sm), StatusChip(label: bandLabel(p.score!.riskBand!), tone: bandTone(p.score!.riskBand!))]),
          ],
          if (p.score!.badges.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final b in p.score!.badges) StatusChip(label: _badgeLabels[b] ?? b, icon: Icons.military_tech, tone: ChipTone.success)]),
          ],
          if (!p.isCrew) ...[const SizedBox(height: Space.md), ScoreSparkline(history: p.score!.history)],
        ],
        if (p.rewards.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('Honours (demo values)', style: t.labelLarge?.copyWith(color: c.muted)),
          const SizedBox(height: Space.xs),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final r in p.rewards) StatusChip(label: r, icon: Icons.workspace_premium, tone: ChipTone.warning)]),
        ],
      ]),
      if (p.requiredPpe.isNotEmpty && !p.isCrew)
        _Panel(title: 'PPE required in ${p.zone?.code ?? 'zone'}', icon: Icons.engineering, children: [
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [for (final k in p.requiredPpe) StatusChip(label: k.label, icon: k.icon)]),
        ]),
      if (p.supervisorStats != null)
        _Panel(title: 'Team & reviews (30 days)', icon: Icons.supervisor_account, children: [
          Wrap(spacing: Space.x2, runSpacing: Space.md, children: [
            _Big(label: 'Team', value: p.supervisorStats!.teamSize),
            _Big(label: 'Decided', value: p.supervisorStats!.decided30d),
            _Big(label: 'On time', value: p.supervisorStats!.onTime),
            _Big(label: 'Breaches', value: p.supervisorStats!.breaches),
            _Big(label: 'Pending', value: p.supervisorStats!.pending),
            _Big(label: 'Reliability', value: p.supervisorStats!.reliability, suffix: '%'),
          ]),
        ]),
      if (!p.isCrew)
        _Panel(title: 'Hazards & SOS', icon: Icons.warning_amber, children: [
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final st in const ['OPEN', 'ACKNOWLEDGED', 'CLOSED', 'REJECTED']) StatusChip(label: '${p.hazardCounts[st] ?? 0} ${st.toLowerCase()}', tone: st == 'OPEN' ? ChipTone.warning : (st == 'CLOSED' ? ChipTone.success : ChipTone.neutral)),
            StatusChip(label: '${p.sosCount} SOS', icon: Icons.sos, tone: p.sosCount > 0 ? ChipTone.danger : ChipTone.neutral),
            if (p.crisisAccounted != null) StatusChip(label: 'Crisis: ${p.crisisAccounted!.toLowerCase()}', tone: p.crisisAccounted == 'SAFE' ? ChipTone.success : ChipTone.crisis),
          ]),
          for (final h in p.hazards)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text('${h.category.replaceAll('_', ' ').toLowerCase()} · ${h.status.toLowerCase()}${h.severity == null ? '' : ' · ${h.severity!.toLowerCase()}'}${h.createdAt == null ? '' : ' · ${relativeTime(h.createdAt!)}'}', style: t.bodyMedium),
            ),
        ]),
      if (!p.isCrew)
        _Panel(title: 'Health & certifications', icon: Icons.health_and_safety, children: [
          _Facts(facts: [('Blood group', p.bloodGroup ?? dash), ('Medical notes', p.medicalNotes ?? dash)]),
          const SizedBox(height: Space.md),
          if (p.certifications.isEmpty)
            Text('No certifications recorded', style: t.bodyMedium?.copyWith(color: c.muted))
          else
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final cert in p.certifications)
                StatusChip(
                  label: cert.expiresAt == null ? cert.name : '${cert.name} · until ${DateFormat('d MMM y').format(cert.expiresAt!)}',
                  icon: Icons.workspace_premium,
                  tone: p.expiring.any((e) => e.name == cert.name) ? (p.expiring.firstWhere((e) => e.name == cert.name).expired ? ChipTone.danger : ChipTone.warning) : ChipTone.success,
                ),
            ]),
        ]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < panels.length; i++) ...[if (i > 0) const SizedBox(height: Space.lg), StaggerIn(index: i, child: panels[i])],
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: c.amberText), const SizedBox(width: Space.sm), Expanded(child: Text(title, style: t.titleMedium))]),
        const SizedBox(height: Space.md),
        ...children,
      ]),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 560 ? 2 : 1;
      final w = (box.maxWidth - Space.lg * (cols - 1)) / cols;
      return Wrap(spacing: Space.lg, runSpacing: Space.md, children: [
        for (final f in facts)
          SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.$1, style: t.labelMedium?.copyWith(color: c.muted)),
              Text(f.$2, style: t.bodyLarge),
            ]),
          ),
      ]);
    });
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, this.prefix = '', this.suffix = '', this.tail});
  final String label;
  final int? value;
  final String prefix;
  final String suffix;
  final String? tail;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final st = t.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: t.labelMedium?.copyWith(color: c.muted)),
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        if (prefix.isNotEmpty && value != null) Text(prefix, style: st),
        AnimatedCounter(value: value, suffix: suffix, style: st),
        if (tail != null) ...[const SizedBox(width: Space.xs), Text(tail!, style: t.bodySmall?.copyWith(color: c.muted))],
      ]),
    ]);
  }
}
