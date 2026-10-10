# Mine Guardian shared contract v1

Authoritative summary lives in CLAUDE.md section 5 and in code:
`backend/src/contracts/{enums,events}.js`, `backend/src/contracts/routes.md`,
`mobile/lib/contracts/*.dart`. Never rename a name; changes need a single `CONTRACT:` commit.

## Additive change (CONTRACT commit): admin-designated emergency exit
- `Zone.evacExitId` (string, layout exit id, default null = nearest safe exit decided on the phone).
- `PUT /api/zones/:id/evac-exit` (admin) body `{ exitId: string | null }`; unknown id -> 400 `INVALID_EXIT` with `details.validExitIds`; audited as `ZONE_EVAC_EXIT_SET`. Listed in `routes.additive.md`.
- Read back as `zone.evacExitId` in `GET /api/auth/me`, `evacExitId` in `GET /api/zones/:id` and in each zone of `GET /api/admin/overview`. No new socket event or enum.
