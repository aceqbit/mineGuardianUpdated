import 'package:equatable/equatable.dart';

import '../../../core/location/location_service.dart';
import '../../../core/models/mine_layout.dart';
import '../data/evac_graph.dart';
import '../data/nav_logic.dart';

/// Distance from the route beyond which the worker is told they are off route.
const double offRouteThresholdM = 30;

/// Within this many metres of the exit point the worker counts as arrived.
const double arrivedRadiusM = 25;

enum SosSendStatus { idle, sending, sent, savedOffline, failed }

/// One LineString feature of crisis:routes for this worker.
class ControlRoute extends Equatable {
  const ControlRoute({required this.rank, required this.points, required this.exitName, required this.etaSec, required this.recommended});
  final int rank;
  final List<GeoPoint> points;
  final String exitName;
  final double etaSec;
  final bool recommended;
  @override
  List<Object?> get props => [rank, points.length, exitName, etaSec, recommended];
}

class SosState extends Equatable {
  const SosState({
    this.evacOnly = false,
    this.status = SosSendStatus.idle,
    this.sentAt,
    this.retries = 0,
    this.layout,
    this.zoneCode,
    this.fix,
    this.offlineRoute,
    this.positionUnknown = false,
    this.controlRoutes = const [],
    this.assignedRank,
    this.cancelled = false,
    this.hazards = const [],
    this.sosId,
    this.alternatives = const [],
    this.selectedExitId,
    this.targetReason = TargetReason.nearest,
    this.workerPickedExitId,
    this.simulating = false,
  });

  final bool evacOnly;
  final SosSendStatus status;
  final DateTime? sentAt;
  final int retries;
  final MineLayoutData? layout;
  final String? zoneCode;
  final LocationFix? fix;
  final EvacRoute? offlineRoute;
  final bool positionUnknown;
  final List<ControlRoute> controlRoutes;
  final int? assignedRank;
  final bool cancelled;
  final List<CachedHazard> hazards;
  final String? sosId;

  /// Up to 3 on-device routes, best first; [offlineRoute] is the selected one.
  final List<EvacRoute> alternatives;
  final String? selectedExitId;

  /// Why [offlineRoute] was chosen (designated exit, nearest, worker choice...).
  final TargetReason targetReason;

  /// Set only when the worker taps a route chip; overrides the designated exit.
  final String? workerPickedExitId;

  /// True while the demo walk simulator is feeding positions (evacuation view only).
  final bool simulating;

  /// Metres from the current fix to the selected on-device route (null when unknown).
  double? get offRouteM {
    final f = fix, r = offlineRoute;
    if (f == null || r == null) return null;
    return EvacGraph.distanceToRouteM(GeoPoint(f.lat, f.lng), r);
  }

  bool get offRoute => (offRouteM ?? 0) > offRouteThresholdM;

  /// Metres to the target exit (straight line), null without a fix or route.
  double? get distanceToTargetM {
    final f = fix, r = offlineRoute;
    if (f == null || r == null) return null;
    return haversineM(GeoPoint(f.lat, f.lng), r.exit.point);
  }

  bool get arrived => (distanceToTargetM ?? double.infinity) <= arrivedRadiusM;

  /// The route the control room wants this worker to take (assigned rank, else recommended).
  ControlRoute? get activeControlRoute {
    if (controlRoutes.isEmpty) return null;
    if (assignedRank != null) {
      final a = controlRoutes.where((r) => r.rank == assignedRank).firstOrNull;
      if (a != null) return a;
    }
    return controlRoutes.where((r) => r.recommended).firstOrNull ?? controlRoutes.first;
  }

  SosState copyWith({
    SosSendStatus? status,
    DateTime? sentAt,
    int? retries,
    MineLayoutData? layout,
    String? zoneCode,
    LocationFix? fix,
    EvacRoute? offlineRoute,
    bool clearOfflineRoute = false,
    bool? positionUnknown,
    List<ControlRoute>? controlRoutes,
    int? assignedRank,
    bool? cancelled,
    List<CachedHazard>? hazards,
    String? sosId,
    List<EvacRoute>? alternatives,
    String? selectedExitId,
    TargetReason? targetReason,
    String? workerPickedExitId,
    bool? simulating,
  }) =>
      SosState(
        evacOnly: evacOnly,
        status: status ?? this.status,
        sentAt: sentAt ?? this.sentAt,
        retries: retries ?? this.retries,
        layout: layout ?? this.layout,
        zoneCode: zoneCode ?? this.zoneCode,
        fix: fix ?? this.fix,
        offlineRoute: clearOfflineRoute ? null : (offlineRoute ?? this.offlineRoute),
        positionUnknown: positionUnknown ?? this.positionUnknown,
        controlRoutes: controlRoutes ?? this.controlRoutes,
        assignedRank: assignedRank ?? this.assignedRank,
        cancelled: cancelled ?? this.cancelled,
        hazards: hazards ?? this.hazards,
        sosId: sosId ?? this.sosId,
        alternatives: alternatives ?? this.alternatives,
        selectedExitId: selectedExitId ?? this.selectedExitId,
        targetReason: targetReason ?? this.targetReason,
        workerPickedExitId: workerPickedExitId ?? this.workerPickedExitId,
        simulating: simulating ?? this.simulating,
      );

  SosState withEvacOnly(bool v) => SosState(
        evacOnly: v,
        status: status,
        sentAt: sentAt,
        retries: retries,
        layout: layout,
        zoneCode: zoneCode,
        fix: fix,
        offlineRoute: offlineRoute,
        positionUnknown: positionUnknown,
        controlRoutes: controlRoutes,
        assignedRank: assignedRank,
        cancelled: cancelled,
        hazards: hazards,
        sosId: sosId,
        alternatives: alternatives,
        selectedExitId: selectedExitId,
        targetReason: targetReason,
        workerPickedExitId: workerPickedExitId,
        simulating: simulating,
      );

  @override
  List<Object?> get props => [evacOnly, status, sentAt, retries, layout?.version, zoneCode, fix?.lat, fix?.lng, offlineRoute?.distanceM, positionUnknown, controlRoutes, assignedRank, cancelled, hazards.length, sosId, alternatives.map((r) => r.exit.id).toList(), selectedExitId, targetReason, workerPickedExitId, simulating];
}
