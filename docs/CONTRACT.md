# Mine Guardian shared contract v1

Authoritative summary lives in CLAUDE.md section 5 and in code:
`backend/src/contracts/{enums,events}.js`, `backend/src/contracts/routes.md`,
`mobile/lib/contracts/*.dart`. Never rename a name; changes need a single `CONTRACT:` commit.

## Change (CONTRACT commit): email identity and email OTP
- The login identity is a real email + password (Firebase email/password). Phone numbers are not part of login or sign-up. `LOGIN_EMAIL_DOMAIN` and the hidden phone-derived email are removed.
- `User.email` (required, unique, lower-case) replaces `User.loginEmail`. `User.phone.e164` is only an optional contact number (not unique, not collected at sign-up) used for SOS calls/SMS; `emergencyContact` is no longer collected.
- `POST /api/auth/signup` body: `email` (no `phone`, no `emergencyContact`). Errors: `EMAIL_TOKEN_MISMATCH` (400, token email differs), `EMAIL_NOT_VERIFIED` (403). `PHONE_TOKEN_MISMATCH` and `INVALID_PHONE` are gone.
- `POST /api/auth/otp/send` (no body) emails a 6-digit code to the signed-in identity's email and returns `{sent, to (masked), cooldownSec, expiresInSec}`; `POST /api/auth/otp/verify {code}`. The API never returns a code. Errors: `OTP_NOT_CONFIGURED` (503), `OTP_COOLDOWN`, `OTP_LIMIT`, `OTP_SEND_FAILED`, `CODE_EXPIRED`, `WRONG_CODE`, `TOO_MANY_ATTEMPTS`. Collection `otp_codes` (hash + bookkeeping, TTL). Audited `OTP_SENT`, `OTP_VERIFIED`.
- Env: `OTP_REQUIRED=true`, `GMAIL_USER`, `GMAIL_APP_PASSWORD`, `TWILIO_CALL_ALLOWLIST`. No new socket event or enum.

## Additive change (CONTRACT commit): admin-designated emergency exit
- `Zone.evacExitId` (string, layout exit id, default null = nearest safe exit decided on the phone).
- `PUT /api/zones/:id/evac-exit` (admin) body `{ exitId: string | null }`; unknown id -> 400 `INVALID_EXIT` with `details.validExitIds`; audited as `ZONE_EVAC_EXIT_SET`. Listed in `routes.additive.md`.
- Read back as `zone.evacExitId` in `GET /api/auth/me`, `evacExitId` in `GET /api/zones/:id` and in each zone of `GET /api/admin/overview`. No new socket event or enum.

## Additive change (CONTRACT commit X0): add-on pack X (CLAUDE.md section 23)
- Enums: `ROUTE_MODE` (LEAST_HINDRANCE, MOST_LIGHT, MOST_AID, DIRECT), `AID_TYPE` (FIRST_AID, TOOL_STATION, PHONE, SCSR_CACHE, FIRE_EXTINGUISHER), `POSITION_SOURCE` (GPS, FUSED, PDR), `SAFETY_ITEM_KIND` (RULE, REACT, PREVENT, LESSON), `VOICE_CALL_STATUS` (QUEUED, RINGING, IN_PROGRESS, COMPLETED, FAILED, DRY_RUN), `PRESENCE` (LIVE, STALE, OFFLINE).
- Server→client: `profile:updated {userId, changed[]}`, `tracking:positions {positions[]}` (1 s throttle), `safety:feed {date, version}`, `voice:call_status {callId, status, targetLabel}`.
- `gps:update` takes optional `headingDeg` [0,360), `speedMps` [0,20], `source` (POSITION_SOURCE, default GPS), `tunnelId`; `GpsUpdated` carries them (null when absent). Old clients are unaffected.
- Bus: `ProfileChanged{userId, changed[]}`, `SafetyFeedUpdated{date, version}`.
- REST (listed in `routes.additive.md`): `/api/profiles*`, `/api/tracking/{live,surface-route}`, `/api/voice/{call,call/:callId/hangup,status}`, `/api/safety-feed{,/today,/refresh}`.
- Collections: `safety_feed`, `voice_calls`, `live_positions`. Layout: `kind: aid` points and optional tunnel `lightLux`.
- Flutter routes: `/worker/profiles /supervisor/profiles /admin/profiles /profiles/:userId /worker/map /supervisor/live-map /admin/live-map /worker/safety`.
- Packages (only manifest edit since Step 0): Flutter `sensors_plus`, `video_player`; Node `ws`.
