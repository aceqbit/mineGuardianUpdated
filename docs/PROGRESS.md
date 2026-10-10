# Progress

| Step | Title | Status |
|---|---|---|
| S0.1 | Backend skeleton and core services | PASS (tests); boot needs .env |
| S0.2 | Models, layout, seed, /me | PASS (tests, layout); seed needs Firebase+Mongo |
| S0.3 | Flutter foundation | PASS (analyze 0, tests); flutterfire configure MANUAL |
| S0.4 | Design system and UI kit | PASS (analyze 0, tests, images 12/12); visual check MANUAL |
| P1.1 | Auth/users/zones API | PASS (tests) |
| P1.2 | Login screen | PASS (analyze, tests, 3-width render); real-phone login MANUAL |
| P1.3 | Sign-up flow | PASS (analyze, 3-width render test); end-to-end create MANUAL |
| P1.4 | Worker Home | PASS (analyze, 3-width test with neutral stats) |
| P1.5 | Capture + quality gate | PASS (analyze, gate/framing unit tests); camera, ML Kit and blur calibration MANUAL |
| P1.6 | Check-in upload API + StatusTicker | PASS (backend 26 tests, ticker 3-width test); phone upload MANUAL |
| P1.7 | Offline outbox + sync engine + indicator | PASS (8 engine tests, 53 total); airplane-mode test MANUAL |
| P1.8 | Report Safety Hazard | PASS (backend 31 tests, 3-width render); phone/offline report MANUAL |
| P1.9 | SOS + panic screen + offline evac map | PASS (backend 33, 6 evac-graph tests, 4 SOS screen tests incl. offline queue); real-phone SOS/SMS/offline MANUAL |
| P1.10 | Supervisor Home live feed | PASS (backend 34, 6 feed-bloc tests incl. live merge/optimistic rollback) |
| P1.11 | Admin Home | PASS (3-width render x crisis on/off); backend overview/supervisors added in P1.10 commit |
| P1.12 | Simulators + p1-smoke + audit | PASS live 14/14 (real Mongo + Firebase Auth) |
| P2.0 | Prep (eval photos + labels) | MANUAL: 30 eval photos + labels.json are yours to make |
| P2.1 | AI analyser core | PASS (22 tests: guardrails, failure policy, mock, schemas); real-key checks MANUAL |
| P2.2 | Tools, tool loop, fusion, eval | PASS (72 backend tests: fusion rules a-h, YOLO parse/ONNX decode, metrics); eval run + real keys MANUAL |
| P2.3 | Wire the analyser into the system | PASS (76 tests incl. job queue); live pipeline run needs Mongo/Firebase = MANUAL |
| P2.4 | Compliance review API, decision rules, PDF, review card UI | PASS (86 backend tests, 9 Flutter tests at 360/768/1280); live PDF/photo needs Firebase = MANUAL |
| P2.5 | Scoring engine, leaderboard, risk bands | PASS (99 backend tests incl. 13 formula tests; 3 Flutter widget tests); live recompute needs Mongo = MANUAL |
| P2.6 | Rewards (monthly honours, cron, demo history seed) and rewards UI | PASS (103 backend tests, 3 Flutter widget tests); seed:history needs a seeded Mongo = MANUAL |
| P2.7 | Admin normal mode: SLA watchdog, reliability, compensation, hazard audit, daily PDF reports + UI | PASS (111 backend tests, 6 Flutter widget tests); live cron/PDF upload = MANUAL |
| P2.8 | Crisis engine: blast-first activation, merge, positions, accounted, resolve + report, public tracking page | PASS (121 backend tests on pure rules); live blast/Twilio dry-run/Mongo = MANUAL (p2-smoke) |
| P2.9 | Rerouter: Tobler graph, hazard constraints/multipliers, A*, Yen, ranking, assignment, crisis routes API | PASS (139 backend tests: A* == Dijkstra on 50 pairs, blocked edge changes rank 1, CRITICAL hazard removes edges, 13-worker recompute ~10 ms) |
| P2.10 | Crisis console, supervisor crisis view, post-crisis report, global overlays (flash/siren/banners) | PASS (110 Flutter tests, analyze clean); siren audio and vibration on a real device = MANUAL |
| P2.11 | Broadcast: scoped send (supervisor = own zone), emit-first, EMERGENCY SMS to offline, acks, replies, sticky banners, composer UI | PASS (146 backend, 117 Flutter tests); real devices/Twilio = MANUAL |
| P2.12 | Emergency contacts: dial-target blocklist guard (UNSAFE_DIAL_TARGET), call/SMS/notify-all, seed, UI with real-number warning | PASS (152 backend incl. blocklist tests, 121 Flutter tests) |
| P2.13 | p2-smoke, adversarial set format, Phase 2 audit and payload docs | PASS live 13/13 (mock AI, local storage, dry-run Twilio) |
| I.1 | Contract check (JS) + route check (Dart) | PASS offline part (29/29); live route probes MANUAL |
| I.3 | Demo runbook | Written (docs/DEMO_RUNBOOK.md) |
| I.4 | Final audit | Written (docs/FINAL_AUDIT.md) with the manual list |
| W3 | Read-aloud (flutter_tts, approved pubspec exception): first aid, evacuation protocol, emergency broadcasts | PASS (analyze clean, widget test); voice quality on a real device = MANUAL |
| W4 | Live camera capture on web too (kIsWeb gates removed), pinch zoom, camera failure falls back to gallery | PASS (analyze clean, 121 tests); real-camera check on phone = MANUAL |
| W2 | Live GPS map (flutter_map + OSM tiles, offline-safe), explicit target pin, 3 on-device alternative routes, auto re-plan on 10 m movement, off-route and arrived states | PASS (130 Flutter tests incl. alternativeRoutes + 7 widget tests at 360/768/1280, light/dark); note: hazard:new socket events do not reach miners, so re-planning uses cached hazards + layout refresh every 30 s; real GPS walk = MANUAL |
| W5 | OTP login via Firebase phone auth: Password / SMS code switch, 6-digit entry, 30 s resend cooldown, 5-try lockout, "Enable OTP login" offer after a password login (links the phone to the same Firebase uid, so no backend or contract change); sign-in with an unlinked phone deletes the empty Firebase user it would create | PASS (145 Flutter tests: 8 bloc + 8 widget OTP tests; analyze clean). MANUAL: enable Phone provider in Firebase console, add Android SHA-1, add test numbers; real SMS delivery. Sign-up wizard unchanged: new accounts are offered OTP linking at their first password login |
| W6 | UI polish through the shared kit: staggered entrance on every AdaptiveGrid, haptic click on MgButton / MediaTile, skeleton loader on the broadcast screen | PASS (145 Flutter tests, analyze clean) |
| P0 | Hotfix: live camera no longer dies on web (flash/zoom probed separately, resolution fallback, 15 s timeout, device-camera and gallery escape routes); voice: per-platform natural speed, best-voice auto pick, sentence pauses, Voice and speed sheet saved on the phone | PASS (analyze clean, 149 Flutter tests incl. voice ranking); camera in a real browser/phone and voice quality = MANUAL |
| P1 | CONTRACT: admin-designated emergency exit per zone (Zone.evacExitId, PUT /api/zones/:id/evac-exit, read in /me, zone detail and admin overview) + admin exit picker on zone cards | PASS (157 backend tests incl. exit validation, contract-check 85/85 live, 149 Flutter tests, analyze clean) |
| P2 | OTP gate on every login and sign-up (Firebase phone auth): number + password, then SMS code (first time links the phone, later logins re-verify), stepper UI, 30 s resend, 5-try lock, sign-out on any failure, sign-up deletes the new account if the phone is not verified; OTP_REQUIRED=false dev switch | PASS (158 Flutter tests: 17 gate tests + widgets at 360/768/1280 light/dark; analyze clean). MANUAL: Firebase console (Phone provider, SHA-1, test numbers), real SMS. Known limit: the gate is enforced in the app; the backend still accepts a password-only Firebase token (hardening would need a backend change) |
| P3 | Navigation v2: target priority (worker pick > admin-designated exit > nearest safe exit, with blocked-exit fallback and a visible reason), turn-by-turn steps, route progress (travelled vs remaining), smoothly animated position with heading, ETA that ticks, demo walk simulator (evacuation view, debug or NAV_SIMULATE) | PASS (nav_logic unit tests incl. target rules, turns, progress, simulator; widget tests; analyze clean). MANUAL: real GPS walk |
| P4a | Palette fixes: contrast audit test (WCAG AA over every text/background pair, light and dark) found 10 failing pairs; fixed success/danger/warning/muted, added amberText, solid-fill tokens (white-text safe in dark mode), surfaceTint, medals, positionBlue; no raw Color(0x...) left on map screens | PASS (228 Flutter tests, analyze clean) |
