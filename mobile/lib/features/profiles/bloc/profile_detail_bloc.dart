import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/profile_models.dart';
import '../data/profiles_repository.dart';

enum DetailStatus { loading, ready, failure }

class ProfileDetailState extends Equatable {
  const ProfileDetailState({this.status = DetailStatus.loading, this.profile, this.saving = false, this.saveError, this.savedAt, this.error, this.liveTick = 0});
  final DetailStatus status;
  final ProfileDetail? profile;
  final bool saving;
  final String? saveError;
  final DateTime? savedAt;
  final String? error;

  /// Bumped on each live refresh (drives the pulse).
  final int liveTick;

  ProfileDetailState copyWith({DetailStatus? status, ProfileDetail? profile, bool? saving, String? saveError, bool clearSaveError = false, DateTime? savedAt, String? error, int? liveTick}) => ProfileDetailState(
        status: status ?? this.status,
        profile: profile ?? this.profile,
        saving: saving ?? this.saving,
        saveError: clearSaveError ? null : (saveError ?? this.saveError),
        savedAt: savedAt ?? this.savedAt,
        error: error ?? this.error,
        liveTick: liveTick ?? this.liveTick,
      );

  @override
  List<Object?> get props => [status, profile, saving, saveError, savedAt, error, liveTick];
}

sealed class ProfileDetailEvent extends Equatable {
  const ProfileDetailEvent();
  @override
  List<Object?> get props => [];
}

class ProfileDetailStarted extends ProfileDetailEvent {
  const ProfileDetailStarted();
}

class ProfileSaved extends ProfileDetailEvent {
  const ProfileSaved(this.changes);
  final Map<String, dynamic> changes;
  @override
  List<Object?> get props => [changes];
}

class _LiveRefresh extends ProfileDetailEvent {
  const _LiveRefresh();
}

/// One profile (CLAUDE.md section 23.2). Refetches when `profile:updated` names this user, or `score:updated` arrives for self.
class ProfileDetailBloc extends Bloc<ProfileDetailEvent, ProfileDetailState> {
  ProfileDetailBloc({required ProfilesRepository repo, required SocketService socket, required this.userId, required bool isSelf})
      : _repo = repo,
        super(const ProfileDetailState()) {
    on<ProfileDetailStarted>((e, emit) async {
      try {
        emit(state.copyWith(status: DetailStatus.ready, profile: await _repo.detail(userId)));
      } on ApiException catch (x) {
        emit(state.copyWith(status: state.profile == null ? DetailStatus.failure : DetailStatus.ready, error: x.statusCode == 403 ? 'This profile is outside your scope.' : x.message));
      }
    });
    on<_LiveRefresh>((e, emit) async {
      try {
        emit(state.copyWith(profile: await _repo.detail(userId), liveTick: state.liveTick + 1));
      } on ApiException {
        // keep what is on screen
      }
    }, transformer: (events, mapper) => events.debounceTime(const Duration(milliseconds: 250)).switchMap(mapper));
    on<ProfileSaved>((e, emit) async {
      emit(state.copyWith(saving: true, clearSaveError: true));
      try {
        emit(state.copyWith(saving: false, profile: await _repo.patch(userId, e.changes), savedAt: DateTime.now()));
      } on ApiException catch (x) {
        emit(state.copyWith(saving: false, saveError: x.message));
      }
    });
    _subs.add(socket.on(SocketEvents.profileUpdated).where((env) => '${env.data['userId']}' == userId).listen((_) => add(const _LiveRefresh())));
    if (isSelf) _subs.add(socket.on(SocketEvents.scoreUpdated).listen((_) => add(const _LiveRefresh())));
  }

  final ProfilesRepository _repo;
  final String userId;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
