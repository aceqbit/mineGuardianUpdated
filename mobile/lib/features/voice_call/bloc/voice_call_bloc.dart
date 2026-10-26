import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../contracts/enums.dart';
import '../../../contracts/socket_events.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../data/voice_repository.dart';

enum CallPhase { idle, placing, active, done, error }

class VoiceCallState extends Equatable {
  const VoiceCallState({this.phase = CallPhase.idle, this.callId, this.status, this.dryRun = false, this.mode, this.statusUpdates = true, this.message});
  final CallPhase phase;
  final String? callId;
  final VoiceCallStatus? status;
  final bool dryRun;
  final String? mode;
  final bool statusUpdates;
  final String? message;

  @override
  List<Object?> get props => [phase, callId, status, dryRun, mode, statusUpdates, message];
}

sealed class VoiceCallEvent extends Equatable {
  const VoiceCallEvent();
  @override
  List<Object?> get props => [];
}

class VoiceCallRequested extends VoiceCallEvent {
  const VoiceCallRequested({this.reason});
  final String? reason;
  @override
  List<Object?> get props => [reason];
}

class VoiceCallHungUp extends VoiceCallEvent {
  const VoiceCallHungUp();
}

class VoiceCallReset extends VoiceCallEvent {
  const VoiceCallReset();
}

class _Status extends VoiceCallEvent {
  const _Status(this.status);
  final VoiceCallStatus status;
  @override
  List<Object?> get props => [status];
}

/// One AI voice-agent call to one target (CLAUDE.md section 23.5). The tap places it at once; status arrives live
/// over `voice:call_status`.
class VoiceCallBloc extends Bloc<VoiceCallEvent, VoiceCallState> {
  VoiceCallBloc({required VoiceRepository repo, required SocketService socket, required this.targetType, required this.targetId})
      : _repo = repo,
        super(const VoiceCallState()) {
    on<VoiceCallRequested>((e, emit) async {
      if (state.phase == CallPhase.placing || state.phase == CallPhase.active) return;
      emit(const VoiceCallState(phase: CallPhase.placing, status: VoiceCallStatus.queued));
      try {
        final c = await _repo.call(targetType: targetType, targetId: targetId, reason: e.reason);
        emit(VoiceCallState(phase: c.status.isFinal ? CallPhase.done : CallPhase.active, callId: c.callId, status: c.status, dryRun: c.dryRun, mode: c.mode, statusUpdates: c.statusUpdates));
      } on ApiException catch (x) {
        emit(VoiceCallState(phase: CallPhase.error, message: voiceErrorText(x)));
      }
    });
    on<_Status>((e, emit) {
      if (state.callId == null) return;
      emit(VoiceCallState(phase: e.status.isFinal ? CallPhase.done : CallPhase.active, callId: state.callId, status: e.status, dryRun: state.dryRun, mode: state.mode, statusUpdates: state.statusUpdates));
    });
    on<VoiceCallHungUp>((e, emit) async {
      final id = state.callId;
      if (id == null) return;
      try {
        add(_Status(await _repo.hangup(id)));
      } on ApiException catch (x) {
        emit(VoiceCallState(phase: CallPhase.error, callId: id, message: voiceErrorText(x)));
      }
    });
    on<VoiceCallReset>((e, emit) => emit(const VoiceCallState()));
    _sub = socket.on(SocketEvents.voiceCallStatus).listen((env) {
      if ('${env.data['callId']}' != state.callId) return;
      try {
        add(_Status(VoiceCallStatus.fromWire('${env.data['status']}')));
      } catch (_) {/* unknown status */}
    });
  }

  final VoiceRepository _repo;
  final String targetType;
  final String targetId;
  StreamSubscription<dynamic>? _sub;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
