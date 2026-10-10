import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/status_chip.dart';
import '../../../app/ui/toast.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../data/rewards_repository.dart';

class RewardsCubit extends Cubit<RewardsViewState> {
  RewardsCubit(this._repo) : super(const RewardsViewState());
  final RewardsRepository _repo;

  Future<void> load({String? month}) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final d = await _repo.list(month: month);
      emit(RewardsViewState(loading: false, data: d, month: month));
    } on ApiException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    }
  }

  Future<String?> publish(String month) async {
    try {
      final r = await _repo.publish(month);
      await load(month: month);
      return '${r['created']} new, ${r['existing']} already published';
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return null;
    }
  }
}

class RewardsViewState {
  const RewardsViewState({this.loading = true, this.data, this.month, this.error});
  final bool loading;
  final RewardsData? data;
  final String? month;
  final String? error;
  RewardsViewState copyWith({bool? loading, String? error, bool clearError = false}) => RewardsViewState(loading: loading ?? this.loading, data: data, month: month, error: clearError ? null : (error ?? this.error));
}

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key, this.repository});
  final RewardsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionBloc>().state;
    final role = session is SessionAuthenticated ? session.user.role : Role.miner;
    return BlocProvider(
      create: (ctx) => RewardsCubit(repository ?? RewardsRepository(api: ctx.read<ApiClient>()))..load(),
      child: _View(isAdmin: role == Role.admin, home: Routes.homeFor(role.wire)),
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this.isAdmin, required this.home});
  final bool isAdmin;
  final String home;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(home)),
        title: const Text('Rewards'),
      ),
      body: BlocBuilder<RewardsCubit, RewardsViewState>(
        builder: (context, s) {
          if (s.loading && s.data == null) return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 3, itemHeight: 110));
          if (s.error != null && s.data == null) return EmptyState(icon: Icons.cloud_off, title: 'Could not load', message: s.error, actionLabel: 'Retry', onAction: () => context.read<RewardsCubit>().load());
          final d = s.data!;
          final shown = s.month ?? (d.months.isEmpty ? null : d.months.first);
          final list = d.rewards.where((r) => shown == null || r.month == shown).toList();
          return ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Widths.form + 120),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Monthly safety honours. Amounts and holidays are demo values.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted)),
                    const SizedBox(height: Space.md),
                    if (d.months.length > 1)
                      SizedBox(
                        height: 40,
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                          for (final m in d.months)
                            Padding(padding: const EdgeInsets.only(right: Space.sm), child: ChoiceChip(label: Text(m), selected: m == shown, onSelected: (_) => context.read<RewardsCubit>().load(month: m))),
                        ]),
                      ),
                    if (isAdmin) ...[
                      const SizedBox(height: Space.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: MgButton(
                          label: 'Publish ${shown ?? 'month'} honours',
                          kind: MgButtonKind.secondary,
                          icon: Icons.publish,
                          onPressed: shown == null
                              ? null
                              : () async {
                                  final msg = await context.read<RewardsCubit>().publish(shown);
                                  if (context.mounted && msg != null) Toast.show(context, msg, kind: ToastKind.success);
                                },
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    if (list.isEmpty)
                      const EmptyState(icon: Icons.emoji_events, title: 'No honours yet', message: 'The top three safety scores are honoured each month.')
                    else
                      for (final r in list) _RewardCard(r: r, showWorker: isAdmin || r.workerName.isNotEmpty && !context.read<SessionBloc>().state.isMiner),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension on SessionState {
  bool get isMiner => this is SessionAuthenticated && (this as SessionAuthenticated).user.role == Role.miner;
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({required this.r, required this.showWorker});
  final RewardItem r;
  final bool showWorker;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final medal = switch (r.rank) { 1 => c.medalGold, 2 => c.medalSilver, _ => c.medalBronze };
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: MgCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.emoji_events, color: medal, size: 36),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: t.titleSmall),
              if (showWorker) Text('${r.workerName} · ${r.employeeId}', style: t.bodySmall?.copyWith(color: c.muted)),
              Text('${r.month} · rank #${r.rank} · score ${r.score}', style: t.bodySmall?.copyWith(color: c.muted)),
              const SizedBox(height: Space.sm),
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                StatusChip(label: '${r.stars} ${r.stars == 1 ? 'star' : 'stars'}', icon: Icons.star, tone: ChipTone.warning),
                if (r.amountInr > 0) StatusChip(label: '₹${r.amountInr} (demo value)', tone: ChipTone.success),
                if (r.extraHolidays > 0) StatusChip(label: '${r.extraHolidays} extra holiday (demo value)', tone: ChipTone.info),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
