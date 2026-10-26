import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/socket_events.dart';
import '../../../core/socket/socket_service.dart';
import '../data/safety_feed_repository.dart';

class SafetyFeedState extends Equatable {
  const SafetyFeedState({this.loading = true, this.availability, this.feed});
  final bool loading;
  final FeedAvailability? availability;
  final SafetyFeed? feed;
  @override
  List<Object?> get props => [loading, availability, feed];
}

sealed class SafetyFeedEvent extends Equatable {
  const SafetyFeedEvent();
  @override
  List<Object?> get props => [];
}

class SafetyFeedStarted extends SafetyFeedEvent {
  const SafetyFeedStarted();
}

/// Today's safety feed (CLAUDE.md section 23.6): cached copy first, then the server; live on `safety:feed`.
class SafetyFeedBloc extends Bloc<SafetyFeedEvent, SafetyFeedState> {
  SafetyFeedBloc({required SafetyFeedRepository repo, required SocketService socket})
      : _repo = repo,
        super(const SafetyFeedState()) {
    on<SafetyFeedStarted>((e, emit) async {
      final old = await _repo.cached();
      if (old != null && state.feed == null) emit(SafetyFeedState(loading: true, availability: FeedAvailability.cached, feed: old));
      final r = await _repo.today();
      emit(SafetyFeedState(loading: false, availability: r.availability, feed: r.feed));
    });
    _sub = socket.on(SocketEvents.safetyFeed).listen((_) => add(const SafetyFeedStarted()));
  }

  final SafetyFeedRepository _repo;
  StreamSubscription<dynamic>? _sub;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
