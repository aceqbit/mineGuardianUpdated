/// Contract v1 socket event names.
class SocketEvents {
  SocketEvents._();

  // server -> client
  static const checkinNew = 'checkin:new';
  static const compliancePredicted = 'compliance:predicted';
  static const complianceReviewed = 'compliance:reviewed';
  static const checkinStatus = 'checkin:status';
  static const hazardNew = 'hazard:new';
  static const hazardClassified = 'hazard:classified';
  static const hazardUpdated = 'hazard:updated';
  static const sosTriggered = 'sos:triggered';
  static const sosCancelled = 'sos:cancelled';
  static const crisisActivated = 'crisis:activated';
  static const crisisRoutes = 'crisis:routes';
  static const crisisRouteAssigned = 'crisis:route_assigned';
  static const crisisUpdated = 'crisis:updated';
  static const crisisPositions = 'crisis:positions';
  static const crisisResolved = 'crisis:resolved';
  static const broadcastMessage = 'broadcast:message';
  static const broadcastReply = 'broadcast:reply';
  static const broadcastStats = 'broadcast:stats';
  static const leaderboardUpdated = 'leaderboard:updated';
  static const scoreUpdated = 'score:updated';
  static const slaBreach = 'sla:breach';
  // add-on pack X
  static const profileUpdated = 'profile:updated';
  static const trackingPositions = 'tracking:positions';
  static const safetyFeed = 'safety:feed';
  static const voiceCallStatus = 'voice:call_status';

  // client -> server
  static const gpsUpdate = 'gps:update';
  static const broadcastAck = 'broadcast:ack';
  static const broadcastReplySend = 'broadcast:reply';

  static const serverToClient = <String>[
    checkinNew, compliancePredicted, complianceReviewed, checkinStatus, hazardNew, hazardClassified,
    hazardUpdated, sosTriggered, sosCancelled, crisisActivated, crisisRoutes, crisisRouteAssigned,
    crisisUpdated, crisisPositions, crisisResolved, broadcastMessage, broadcastReply, broadcastStats,
    leaderboardUpdated, scoreUpdated, slaBreach,
    profileUpdated, trackingPositions, safetyFeed, voiceCallStatus,
  ];
}
