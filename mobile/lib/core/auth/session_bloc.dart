// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../models/session_user.dart';
import 'auth_repository.dart';

// ---- events ----
sealed class SessionEvent extends Equatable {
  const SessionEvent();
  @override
  List<Object?> get props => [];
}

class AppStarted extends SessionEvent {
  const AppStarted();
}

class SessionRefreshed extends SessionEvent {
  const SessionRefreshed();
}

class LoggedIn extends SessionEvent {
  const LoggedIn(this.user);
  final SessionUser user;
  @override
  List<Object?> get props => [user];
}

class LoggedOut extends SessionEvent {
  const LoggedOut();
}

// ---- states ----
sealed class SessionState extends Equatable {
  const SessionState();
  @override
  List<Object?> get props => [];
}

class SessionUnknown extends SessionState {
  const SessionUnknown();
}

class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.user);
  final SessionUser user;
  @override
  List<Object?> get props => [user];
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({required AuthRepository auth, required ApiClient api})
      : _auth = auth,
        _api = api,
        super(const SessionUnknown()) {
    on<AppStarted>(_onStarted);
    on<SessionRefreshed>(_onRefreshed);
    on<LoggedIn>((e, emit) => emit(SessionAuthenticated(e.user)));
    on<LoggedOut>(_onLoggedOut);
  }

  final AuthRepository _auth;
  final ApiClient _api;

  Future<SessionUser?> _fetchMe() async {
    final json = await _api.getJson('/api/auth/me');
    return SessionUser.fromMe(json);
  }

  /// Every app start begins at the login screen. A Firebase session the browser or phone kept from last time is ended, because
  /// a password-only session would skip the emailed code that every login needs.
  Future<void> _onStarted(AppStarted e, Emitter<SessionState> emit) async {
    if (_auth.currentUser != null) {
      try {
        await _auth.signOut();
      } catch (_) {}
    }
    emit(const SessionUnauthenticated());
  }

  Future<void> _onRefreshed(SessionRefreshed e, Emitter<SessionState> emit) async {
    if (state is! SessionAuthenticated) return;
    try {
      final u = await _fetchMe();
      if (u != null) emit(SessionAuthenticated(u));
    } catch (_) {/* keep current session on transient failure */}
  }

  Future<void> _onLoggedOut(LoggedOut e, Emitter<SessionState> emit) async {
    await _auth.signOut();
    emit(const SessionUnauthenticated());
  }
}
