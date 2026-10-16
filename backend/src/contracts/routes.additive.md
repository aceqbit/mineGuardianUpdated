# Additive REST routes (added after contract v1 froze; nothing in routes.md changed)
PUT /api/contacts/:id
GET /api/broadcasts/history
GET /api/broadcasts/replies
PUT /api/zones/:id/evac-exit
POST /api/auth/otp/send
POST /api/auth/otp/verify
GET /api/profiles
GET /api/profiles/:userId
PATCH /api/profiles/:userId
GET /api/tracking/live
GET /api/tracking/surface-route
POST /api/voice/call
POST /api/voice/call/:callId/hangup
POST /api/voice/status
GET /api/safety-feed/today
GET /api/safety-feed
POST /api/safety-feed/refresh
