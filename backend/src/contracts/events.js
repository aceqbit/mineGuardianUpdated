// Shared contract v1: socket + bus event names. Frozen after S0.1.
export const SOCKET_EVENTS = Object.freeze({
  serverToClient: Object.freeze([
    'checkin:new', 'compliance:predicted', 'compliance:reviewed', 'checkin:status',
    'hazard:new', 'hazard:classified', 'hazard:updated',
    'sos:triggered', 'sos:cancelled',
    'crisis:activated', 'crisis:routes', 'crisis:route_assigned', 'crisis:updated', 'crisis:positions', 'crisis:resolved',
    'broadcast:message', 'broadcast:reply', 'broadcast:stats',
    'leaderboard:updated', 'score:updated', 'sla:breach',
    // add-on pack X
    'profile:updated', 'tracking:positions', 'safety:feed', 'voice:call_status',
  ]),
  clientToServer: Object.freeze(['gps:update', 'broadcast:ack', 'broadcast:reply']),
});

export const BUS_EVENTS = Object.freeze([
  'CheckInCreated', 'HazardCreated', 'HazardStatusChanged', 'SosTriggered', 'SosCancelled',
  'GpsUpdated', 'ComplianceReviewed', 'CrisisRequested', 'CrisisActivated', 'CrisisResolved',
  // add-on pack X
  'ProfileChanged', 'SafetyFeedUpdated',
]);
