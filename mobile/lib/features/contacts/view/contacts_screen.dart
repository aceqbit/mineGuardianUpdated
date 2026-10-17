import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/toast.dart';
import '../../../core/api/api_client.dart';
import '../../admin_home/widgets/admin_nav.dart';
import '../../voice_call/widgets/ai_call_button.dart';
import '../data/contacts_repository.dart';

const realNumberWarning = 'Real emergency number. Only call in a real emergency.';

class ContactsState {
  const ContactsState({this.loading = true, this.items = const [], this.error, this.busyId});
  final bool loading;
  final List<EmergencyContactItem> items;
  final String? error, busyId;
}

class ContactsCubit extends Cubit<ContactsState> {
  ContactsCubit(this._repo) : super(const ContactsState());
  final ContactsRepository _repo;

  Future<void> load() async {
    try {
      emit(ContactsState(loading: false, items: await _repo.list()));
    } on ApiException catch (e) {
      emit(ContactsState(loading: false, items: state.items, error: e.message));
    }
  }

  Future<String> _run(String? id, Future<ContactActionResult> Function() action, String what) async {
    emit(ContactsState(loading: false, items: state.items, busyId: id ?? 'all'));
    try {
      final r = await action();
      emit(ContactsState(loading: false, items: state.items));
      return r.dryRun ? '$what (demo mode: logged, nothing was sent)' : what;
    } on ApiException catch (e) {
      emit(ContactsState(loading: false, items: state.items));
      return e.message;
    }
  }

  Future<String> call(EmergencyContactItem c) => _run(c.id, () => _repo.call(c.id), 'Call placed to ${c.name}');
  Future<String> sms(EmergencyContactItem c) => _run(c.id, () => _repo.sms(c.id), 'SMS sent to ${c.name}');
  Future<String> notifyAll() => _run(null, () => _repo.notifyAll(), 'All contacts notified');
}

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key, this.repository, this.openUrl});
  final ContactsRepository? repository;
  final Future<void> Function(Uri)? openUrl;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ContactsCubit(repository ?? ContactsRepository(api: ctx.read<ApiClient>()))..load(),
        child: AdminScaffold(section: AdminSection.contacts, title: 'Emergency contacts', body: _Body(openUrl: openUrl)),
      );
}

Future<bool> _confirm(BuildContext context, {required String title, required String body, required String action, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: danger ? FilledButton.styleFrom(backgroundColor: MgColors.of(ctx).crisis) : null, onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

class _Body extends StatelessWidget {
  const _Body({this.openUrl});
  final Future<void> Function(Uri)? openUrl;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return BlocBuilder<ContactsCubit, ContactsState>(
      builder: (context, s) {
        if (s.loading) return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 5, itemHeight: 110));
        if (s.error != null && s.items.isEmpty) return EmptyState(icon: Icons.cloud_off, title: 'Could not load', message: s.error, actionLabel: 'Retry', onAction: () => context.read<ContactsCubit>().load());
        void toast(String m) => Toast.show(context, m);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Space.lg),
          child: ContentWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: c.warningBg, borderRadius: BorderRadius.circular(Radii.sm)),
                child: Row(children: [Icon(Icons.shield, color: c.warning), const SizedBox(width: Space.sm), Expanded(child: Text('Calls and texts from this screen go to verified team numbers, never to real emergency services. The number shown on each card is what you would dial yourself.', style: t.bodySmall))]),
              ),
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: MgButton(
                  label: 'Notify all contacts',
                  icon: Icons.notifications_active,
                  kind: MgButtonKind.danger,
                  loading: s.busyId == 'all',
                  onPressed: () async {
                    if (!await _confirm(context, title: 'Notify all contacts?', body: 'Every contact below will get a call and an SMS with the current crisis details.', action: 'Notify all', danger: true) || !context.mounted) return;
                    toast(await context.read<ContactsCubit>().notifyAll());
                  },
                ),
              ),
              const SizedBox(height: Space.md),
              if (s.items.isEmpty) const EmptyState(icon: Icons.contact_phone, title: 'No contacts', message: 'Run the seed to add the emergency contacts.'),
              AdaptiveGrid(
                minTileWidth: 320,
                maxColumns: 2,
                fixedTileHeight: 290,
                children: [
                  for (final it in s.items)
                    MgCard(
                      key: ValueKey('contact-${it.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(it.category.icon, color: c.crisis, size: 28),
                          const SizedBox(width: Space.sm),
                          Expanded(child: Text(it.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          // Add-on X5: AI voice agent, one tap. Sized to the 28 px category icon so the fixed-height card does not
                          // grow (28 px still meets the WCAG 2.2 24 px target-size minimum).
                          IconButton(
                            tooltip: 'AI agent call to ${it.name}',
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                            iconSize: 22,
                            color: c.info,
                            icon: const Icon(Icons.support_agent),
                            onPressed: () => showAiCallSheet(context, targetType: 'contact', targetId: it.id, targetLabel: it.name),
                          ),
                        ]),
                        const SizedBox(height: Space.xs),
                        Text(it.displayNumber, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        if (it.notes.isNotEmpty) Text(it.notes, style: t.bodySmall?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                          MgButton(
                            label: 'Dial',
                            icon: Icons.phone,
                            kind: MgButtonKind.secondary,
                            onPressed: () async {
                              if (!await _confirm(context, title: 'Dial ${it.displayNumber}?', body: realNumberWarning, action: 'Dial', danger: true)) return;
                              await (openUrl ?? (u) async { await launchUrl(u); })(Uri.parse(it.telUri));
                            },
                          ),
                          MgButton(
                            label: 'Call via app',
                            icon: Icons.phone_forwarded,
                            loading: s.busyId == it.id,
                            onPressed: () async {
                              if (!await _confirm(context, title: 'Place a call to ${it.name}?', body: 'The app calls the contact\'s verified number with the crisis message.', action: 'Call') || !context.mounted) return;
                              toast(await context.read<ContactsCubit>().call(it));
                            },
                          ),
                          MgButton(
                            label: 'SMS',
                            icon: Icons.sms,
                            kind: MgButtonKind.secondary,
                            onPressed: () async {
                              final m = await context.read<ContactsCubit>().sms(it);
                              if (context.mounted) toast(m);
                            },
                          ),
                        ]),
                      ]),
                    ),
                ],
              ),
            ]),
          ),
        );
      },
    );
  }
}
