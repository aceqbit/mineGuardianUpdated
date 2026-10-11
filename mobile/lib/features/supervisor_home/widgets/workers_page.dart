import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_text_field.dart';
import '../../../contracts/enums.dart';
import '../data/models/feed_item.dart';
import 'worker_card.dart';

enum WorkerFilter { all, notCheckedIn, needsReview, nonCompliant }

extension WorkerFilterLabel on WorkerFilter {
  String get label => switch (this) { WorkerFilter.all => 'All', WorkerFilter.notCheckedIn => 'Not checked in', WorkerFilter.needsReview => 'Needs review', WorkerFilter.nonCompliant => 'Non-compliant' };
  IconData get icon => switch (this) { WorkerFilter.all => Icons.groups, WorkerFilter.notCheckedIn => Icons.person_off, WorkerFilter.needsReview => Icons.pending_actions, WorkerFilter.nonCompliant => Icons.gpp_bad };
}

/// Pure roster filter: the chip first, then a name / employee ID search.
List<WorkerToday> filterWorkers(List<WorkerToday> all, WorkerFilter f, String query) {
  final q = query.trim().toLowerCase();
  bool pass(WorkerToday w) {
    switch (f) {
      case WorkerFilter.all:
        return true;
      case WorkerFilter.notCheckedIn:
        return w.status == 'NOT_CHECKED_IN';
      case WorkerFilter.needsReview:
        return w.status == 'PREDICTED' || w.status == 'FAILED_AI';
      case WorkerFilter.nonCompliant:
        return (w.finalVerdict ?? w.verdict) == Verdict.nonCompliant;
    }
  }

  return [
    for (final w in all)
      if (pass(w) && (q.isEmpty || w.fullName.toLowerCase().contains(q) || w.employeeId.toLowerCase().contains(q))) w,
  ];
}

/// The Workers tab: search, filter chips with counts, and a grid of worker cards.
class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key, required this.workers, required this.onOpenWorker});
  final List<WorkerToday> workers;
  final ValueChanged<WorkerToday> onOpenWorker;

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  final _search = TextEditingController();
  WorkerFilter _filter = WorkerFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = filterWorkers(widget.workers, _filter, _search.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MgTextField(controller: _search, label: 'Search by name or employee ID', prefix: const Icon(Icons.search), onChanged: (_) => setState(() {})),
      const SizedBox(height: Space.md),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in WorkerFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: ChoiceChip(
                avatar: Icon(f.icon, size: 16),
                label: Text('${f.label} · ${filterWorkers(widget.workers, f, '').length}'),
                selected: _filter == f,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ]),
      ),
      const SizedBox(height: Space.lg),
      if (shown.isEmpty)
        const EmptyState(icon: Icons.groups, title: 'No workers match', message: 'Try another filter or search')
      else
        AdaptiveGrid(minTileWidth: 300, maxColumns: 3, spacing: Space.md, fixedTileHeight: 112, children: [for (final w in shown) WorkerCard(worker: w, onTap: () => widget.onOpenWorker(w))]),
    ]);
  }
}
