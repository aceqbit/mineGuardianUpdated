import 'package:equatable/equatable.dart';

import '../../../../contracts/enums.dart';

DateTime _t(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toUtc() ?? DateTime.now().toUtc();

class ReviewSummary extends Equatable {
  const ReviewSummary({this.reviewId, this.verdict, this.confidence, this.critLevel, this.critScore, this.summary, this.emergencyDetected = false, this.emergencyPossible = false, this.action, this.finalVerdict});
  final String? reviewId;
  final Verdict? verdict;
  final double? confidence;
  final Criticality? critLevel;
  final int? critScore;
  final String? summary;
  final bool emergencyDetected;
  final bool emergencyPossible;
  final DecisionAction? action;
  final Verdict? finalVerdict;

  bool get decided => finalVerdict != null || action != null;

  static Verdict? _v(dynamic w) => w is String ? Verdict.fromWire(w) : null;

  factory ReviewSummary.fromJson(Map<String, dynamic> j) {
    final crit = (j['criticality'] as Map?)?.cast<String, dynamic>();
    final em = (j['emergency'] as Map?)?.cast<String, dynamic>();
    return ReviewSummary(
      reviewId: j['reviewId']?.toString(),
      verdict: _v(j['verdict']),
      confidence: (j['overallConfidence'] as num?)?.toDouble(),
      critLevel: crit?['level'] is String ? Criticality.fromWire(crit!['level'] as String) : null,
      critScore: (crit?['score'] as num?)?.round(),
      summary: j['summary'] as String?,
      emergencyDetected: em?['detected'] == true,
      emergencyPossible: em?['possible'] == true,
      action: j['decisionAction'] is String ? DecisionAction.fromWire(j['decisionAction'] as String) : null,
      finalVerdict: _v(j['finalVerdict']),
    );
  }

  ReviewSummary copyWith({Verdict? verdict, double? confidence, Criticality? critLevel, int? critScore, String? summary, bool? emergencyDetected, bool? emergencyPossible, DecisionAction? action, Verdict? finalVerdict, String? reviewId}) => ReviewSummary(
        reviewId: reviewId ?? this.reviewId,
        verdict: verdict ?? this.verdict,
        confidence: confidence ?? this.confidence,
        critLevel: critLevel ?? this.critLevel,
        critScore: critScore ?? this.critScore,
        summary: summary ?? this.summary,
        emergencyDetected: emergencyDetected ?? this.emergencyDetected,
        emergencyPossible: emergencyPossible ?? this.emergencyPossible,
        action: action ?? this.action,
        finalVerdict: finalVerdict ?? this.finalVerdict,
      );

  @override
  List<Object?> get props => [reviewId, verdict, confidence, critLevel, critScore, summary, emergencyDetected, emergencyPossible, action, finalVerdict];
}

sealed class FeedItem extends Equatable {
  const FeedItem();
  String get id;
  DateTime get time;
  bool get isSos => false;
  bool get isEmergency => false;
}

class CheckinFeed extends FeedItem {
  const CheckinFeed({required this.id, required this.workerId, required this.workerName, required this.time, required this.status, this.thumbUrl, this.flags = const [], this.review});
  @override
  final String id;
  final String workerId;
  final String workerName;
  @override
  final DateTime time;
  final CheckinStatus status;
  final String? thumbUrl;
  final List<IntegrityFlag> flags;
  final ReviewSummary? review;

  @override
  bool get isEmergency => review != null && (review!.emergencyDetected || review!.emergencyPossible);

  factory CheckinFeed.fromJson(Map<String, dynamic> j) => CheckinFeed(
        id: (j['checkInId'] ?? j['id']).toString(),
        workerId: (j['workerId'] ?? '').toString(),
        workerName: j['workerName'] as String? ?? 'Worker',
        time: _t(j['capturedAt']),
        status: CheckinStatus.fromWire(j['status'] as String? ?? 'RECEIVED'),
        thumbUrl: j['thumbUrl'] as String?,
        flags: ((j['integrityFlags'] as List?) ?? const []).map((e) => IntegrityFlag.fromWire(e as String)).toList(),
        review: j['review'] is Map ? ReviewSummary.fromJson((j['review'] as Map).cast<String, dynamic>()) : null,
      );

  CheckinFeed copyWith({CheckinStatus? status, ReviewSummary? review}) => CheckinFeed(id: id, workerId: workerId, workerName: workerName, time: time, status: status ?? this.status, thumbUrl: thumbUrl, flags: flags, review: review ?? this.review);

  @override
  List<Object?> get props => [id, workerId, workerName, time, status, thumbUrl, flags, review];
}

class HazardFeed extends FeedItem {
  const HazardFeed({required this.id, required this.reporterName, required this.category, required this.time, required this.status, this.severity, this.thumbUrl, this.lat, this.lng, this.aiSummary, this.emergencyDetected = false, this.acknowledgedAt, this.closedAt, this.closeNote});
  @override
  final String id;
  final String reporterName;
  final HazardCategory category;
  @override
  final DateTime time;
  final HazardStatus status;
  final HazardSeverity? severity;
  final String? thumbUrl;
  final double? lat;
  final double? lng;
  final String? aiSummary;
  final bool emergencyDetected;
  final DateTime? acknowledgedAt;
  final DateTime? closedAt;
  final String? closeNote;

  @override
  bool get isEmergency => emergencyDetected || severity == HazardSeverity.critical;

  factory HazardFeed.fromJson(Map<String, dynamic> j) {
    final loc = (j['locationLatLng'] ?? j['location']) as Map?;
    double? lat, lng;
    if (loc != null && loc['lat'] != null) {
      lat = (loc['lat'] as num).toDouble();
      lng = (loc['lng'] as num).toDouble();
    } else if (loc != null && loc['coordinates'] is List) {
      lng = ((loc['coordinates'] as List)[0] as num).toDouble();
      lat = ((loc['coordinates'] as List)[1] as num).toDouble();
    }
    final ai = (j['ai'] as Map?)?.cast<String, dynamic>();
    final sev = ai?['severity'] ?? j['severity'];
    return HazardFeed(
      id: (j['hazardId'] ?? j['id'] ?? j['_id']).toString(),
      reporterName: j['reporterName'] as String? ?? 'Worker',
      category: HazardCategory.fromWire(j['category'] as String? ?? 'OTHER'),
      time: _t(j['capturedAt'] ?? j['receivedAt'] ?? j['createdAt']),
      status: HazardStatus.fromWire(j['status'] as String? ?? 'OPEN'),
      severity: sev is String ? HazardSeverity.fromWire(sev) : null,
      thumbUrl: j['thumbUrl'] as String?,
      lat: lat,
      lng: lng,
      aiSummary: (ai?['summary'] ?? j['summary']) as String?,
      emergencyDetected: ((ai?['emergency'] ?? j['emergency']) as Map?)?['detected'] == true,
      acknowledgedAt: j['acknowledgedAt'] == null ? null : _t(j['acknowledgedAt']),
      closedAt: j['closedAt'] == null ? null : _t(j['closedAt']),
      closeNote: j['closeNote'] as String?,
    );
  }

  HazardFeed copyWith({HazardStatus? status, HazardSeverity? severity, String? aiSummary, bool? emergencyDetected, DateTime? acknowledgedAt, DateTime? closedAt, String? closeNote}) => HazardFeed(
        id: id,
        reporterName: reporterName,
        category: category,
        time: time,
        status: status ?? this.status,
        severity: severity ?? this.severity,
        thumbUrl: thumbUrl,
        lat: lat,
        lng: lng,
        aiSummary: aiSummary ?? this.aiSummary,
        emergencyDetected: emergencyDetected ?? this.emergencyDetected,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
        closedAt: closedAt ?? this.closedAt,
        closeNote: closeNote ?? this.closeNote,
      );

  @override
  List<Object?> get props => [id, reporterName, category, time, status, severity, thumbUrl, lat, lng, aiSummary, emergencyDetected, acknowledgedAt, closedAt, closeNote];
}

class SosFeed extends FeedItem {
  const SosFeed({required this.id, required this.workerId, required this.workerName, required this.time, this.lat, this.lng, this.phone});
  @override
  final String id;
  final String workerId;
  final String workerName;
  @override
  final DateTime time;
  final double? lat;
  final double? lng;
  final String? phone;

  @override
  bool get isSos => true;
  @override
  bool get isEmergency => true;

  factory SosFeed.fromJson(Map<String, dynamic> j) {
    final loc = (j['locationLatLng'] ?? j['location']) as Map?;
    double? lat, lng;
    if (loc != null && loc['lat'] != null) {
      lat = (loc['lat'] as num).toDouble();
      lng = (loc['lng'] as num).toDouble();
    } else if (loc != null && loc['coordinates'] is List) {
      lng = ((loc['coordinates'] as List)[0] as num).toDouble();
      lat = ((loc['coordinates'] as List)[1] as num).toDouble();
    }
    return SosFeed(id: (j['sosId'] ?? j['id'] ?? j['_id']).toString(), workerId: (j['workerId'] ?? '').toString(), workerName: j['workerName'] as String? ?? 'Worker', time: _t(j['triggeredAt']), lat: lat, lng: lng, phone: j['workerPhone'] as String?);
  }

  @override
  List<Object?> get props => [id, workerId, workerName, time, lat, lng, phone];
}

class WorkerToday extends Equatable {
  const WorkerToday({required this.id, required this.fullName, required this.employeeId, required this.status, this.phone, this.verdict, this.finalVerdict, this.riskBand, this.checkInId, this.capturedAt, this.thumbUrl, this.count = 0});
  final String id;
  final String fullName;
  final String employeeId;
  final String? phone;
  final String status; // NOT_CHECKED_IN or a CHECKIN_STATUS
  final Verdict? verdict;
  final Verdict? finalVerdict;
  final RiskBand? riskBand;

  /// Today's latest check-in: id, when it was captured, its photo link, and how many were received today.
  final String? checkInId;
  final DateTime? capturedAt;
  final String? thumbUrl;
  final int count;

  factory WorkerToday.fromJson(Map<String, dynamic> j) {
    final today = (j['today'] as Map?)?.cast<String, dynamic>() ?? const {};
    Verdict? v(dynamic w) => w is String ? Verdict.fromWire(w) : null;
    return WorkerToday(id: j['id'].toString(), fullName: j['fullName'] as String? ?? '', employeeId: j['employeeId'] as String? ?? '', phone: j['phoneE164'] as String?, status: today['status'] as String? ?? 'NOT_CHECKED_IN', verdict: v(today['verdict']), finalVerdict: v(today['finalVerdict']), checkInId: today['checkInId'] as String?, capturedAt: today['capturedAt'] == null ? null : _t(today['capturedAt']), thumbUrl: today['thumbUrl'] as String?, count: (today['count'] as num?)?.toInt() ?? 0);
  }

  WorkerToday copyWith({String? status, RiskBand? riskBand}) => WorkerToday(id: id, fullName: fullName, employeeId: employeeId, phone: phone, status: status ?? this.status, verdict: verdict, finalVerdict: finalVerdict, riskBand: riskBand ?? this.riskBand, checkInId: checkInId, capturedAt: capturedAt, thumbUrl: thumbUrl, count: count);

  @override
  List<Object?> get props => [id, fullName, employeeId, phone, status, verdict, finalVerdict, riskBand, checkInId, capturedAt, thumbUrl, count];
}
