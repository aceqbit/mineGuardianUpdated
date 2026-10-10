import 'package:equatable/equatable.dart';

import '../data/admin_repository.dart';

enum AdminStatus { loading, ready, failure }

class AdminHomeState extends Equatable {
  const AdminHomeState({this.status = AdminStatus.loading, this.overview, this.supervisors = const [], this.slaBreaches = 0, this.exits = const [], this.notice, this.noticeIsError = false});
  final AdminStatus status;
  final AdminOverview? overview;
  final List<SupervisorRef> supervisors;
  final int slaBreaches;
  final List<ExitRef> exits;
  final String? notice;
  final bool noticeIsError;

  AdminHomeState copyWith({AdminStatus? status, AdminOverview? overview, List<SupervisorRef>? supervisors, int? slaBreaches, List<ExitRef>? exits, String? notice, bool noticeIsError = false, bool clearNotice = false}) => AdminHomeState(
        status: status ?? this.status,
        overview: overview ?? this.overview,
        supervisors: supervisors ?? this.supervisors,
        slaBreaches: slaBreaches ?? this.slaBreaches,
        exits: exits ?? this.exits,
        notice: clearNotice ? null : (notice ?? this.notice),
        noticeIsError: clearNotice ? false : (notice != null ? noticeIsError : this.noticeIsError),
      );

  @override
  List<Object?> get props => [status, overview, supervisors, slaBreaches, exits, notice, noticeIsError];
}
