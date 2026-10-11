import 'package:equatable/equatable.dart';

import '../../../core/location/location_service.dart';
import '../../../core/models/mine_layout.dart';

sealed class SosEvent extends Equatable {
  const SosEvent();
  @override
  List<Object?> get props => [];
}

class SosOpened extends SosEvent {
  const SosOpened({required this.evacOnly});
  final bool evacOnly;
  @override
  List<Object?> get props => [evacOnly];
}

class SosLocationChanged extends SosEvent {
  const SosLocationChanged(this.fix, {this.simulated = false});
  final LocationFix fix;

  /// True for positions from the demo walk simulator.
  final bool simulated;
  @override
  List<Object?> get props => [fix.lat, fix.lng, fix.accuracyM, simulated];
}

class SosQueuedResult extends SosEvent {
  const SosQueuedResult(this.sosId);
  final String? sosId;
  @override
  List<Object?> get props => [sosId];
}

class SosRoutesReceived extends SosEvent {
  const SosRoutesReceived(this.collection);
  final Map<String, dynamic> collection;
  @override
  List<Object?> get props => [collection];
}

class SosRouteAssigned extends SosEvent {
  const SosRouteAssigned(this.rank);
  final int rank;
  @override
  List<Object?> get props => [rank];
}

class SosGpsTick extends SosEvent {
  const SosGpsTick();
}

class SosCancelConfirmed extends SosEvent {
  const SosCancelConfirmed();
}

class SosRetrySend extends SosEvent {
  const SosRetrySend();
}

class SosLayoutLoaded extends SosEvent {
  const SosLayoutLoaded(this.layout);
  final MineLayoutData layout;
  @override
  List<Object?> get props => [layout.version];
}

/// The worker picked one of the alternative routes (by exit id).
class SosRouteSelected extends SosEvent {
  const SosRouteSelected(this.exitId);
  final String exitId;
  @override
  List<Object?> get props => [exitId];
}

/// The worker pinned a start on the map (null = back to the live GPS position).
class SosStartPinned extends SosEvent {
  const SosStartPinned(this.point);
  final GeoPoint? point;
  @override
  List<Object?> get props => [point?.lat, point?.lng];
}

/// The worker chose the end of the route: an exit or refuge id (null = automatic nearest safe exit).
class SosDestinationSelected extends SosEvent {
  const SosDestinationSelected(this.id);
  final String? id;
  @override
  List<Object?> get props => [id];
}

/// Periodic re-read of cached hazards and the layout version.
class SosRefreshTick extends SosEvent {
  const SosRefreshTick();
}

/// Start / stop the demo walk simulator (evacuation view only; never during a real SOS).
class SosSimulateToggled extends SosEvent {
  const SosSimulateToggled();
}
