import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/location/tracking_controller.dart';

sealed class LiveTrackingEvent extends Equatable {
  const LiveTrackingEvent();
  @override
  List<Object?> get props => [];
}

class LiveTrackingWatched extends LiveTrackingEvent {
  const LiveTrackingWatched();
}

class LiveTrackingStatusChanged extends LiveTrackingEvent {
  const LiveTrackingStatusChanged(this.status);
  final TrackingStatus status;
  @override
  List<Object?> get props => [status];
}

class LiveTrackingConsentAnswered extends LiveTrackingEvent {
  const LiveTrackingConsentAnswered(this.granted);
  final bool granted;
  @override
  List<Object?> get props => [granted];
}

class LiveTrackingToggled extends LiveTrackingEvent {
  const LiveTrackingToggled(this.on);
  final bool on;
  @override
  List<Object?> get props => [on];
}

class LiveTrackingState extends Equatable {
  const LiveTrackingState({required this.status});
  final TrackingStatus status;
  @override
  List<Object?> get props => [status];
}

/// The miner's "Live" pill: mirrors [TrackingController] and carries consent / off-switch answers back to it.
class LiveTrackingBloc extends Bloc<LiveTrackingEvent, LiveTrackingState> {
  LiveTrackingBloc({required TrackingController controller})
      : _controller = controller,
        super(LiveTrackingState(status: controller.status)) {
    on<LiveTrackingWatched>((e, emit) async {
      await _sub?.cancel();
      _sub = _controller.status$.listen((s) => add(LiveTrackingStatusChanged(s)));
    });
    on<LiveTrackingStatusChanged>((e, emit) => emit(LiveTrackingState(status: e.status)));
    on<LiveTrackingConsentAnswered>((e, emit) => e.granted ? _controller.grantConsent() : _controller.declineConsent());
    on<LiveTrackingToggled>((e, emit) => _controller.setEnabled(e.on));
  }

  final TrackingController _controller;
  StreamSubscription<TrackingStatus>? _sub;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
