## Context

The Flutter app currently includes an HTTP fallback for the production API and Android allows cleartext traffic. Migration scripts contain reusable default credentials. The frontend also performs several privileged Firestore mutations directly, including user profile/role updates and time-record edits, while the backend already has Firebase token validation and admin authorization helpers. Audio upload code logs Firebase Storage download URLs that may include access tokens.

Firebase security rules are considered properly defined, so this change does not attempt to fix role escalation through rules. Instead, it reduces attack surface by routing privileged mutations through backend endpoints and eliminating avoidable token exposure.

## Goals / Non-Goals

**Goals:**
- Use HTTPS-only production API endpoints in the app.
- Remove insecure migration credential defaults.
- Remove sensitive audio URL logging and replace it with safe metadata logs.
- Add backend endpoints for admin user updates and admin time-record edits.
- Update frontend admin methods to call backend endpoints with Firebase Bearer tokens.

**Non-Goals:**
- Redesign Firebase security rules.
- Replace Firebase Authentication, Firestore, or Firebase Storage.
- Remove existing non-admin Firestore usage.
- Rebuild the full backend architecture.
- Change normal employee workflows except where they benefit from safer API transport/logging.

## Decisions

1. Remove production HTTP fallback instead of keeping it as a retry option.
   - Rationale: retrying from HTTPS to HTTP can leak Firebase ID tokens in the `Authorization` header.
   - Alternative considered: keep HTTP only for debug. That requires flavor-specific manifests and is better handled later if local Android development needs it.

2. Disable Android cleartext traffic at the application manifest level for the main app.
   - Rationale: even if URLs are corrected, manifest-level cleartext permission weakens the transport boundary.
   - Alternative considered: network security config with domain exceptions. No production HTTP domain is required for this change.

3. Require migration credentials from environment variables.
   - Rationale: hardcoded `admin123` and `senha123` can escape into real runs.
   - Alternative considered: prompt interactively. Environment variables are easier for repeatable scripts and automation.

4. Move admin user updates and time-record edits to backend endpoints.
   - Rationale: backend authorization and audit behavior are harder to bypass than client-side role checks.
   - Alternative considered: rely only on Firebase Rules. The rules may be strong, but backend mediation gives clearer control and logging.

5. Redact audio URLs from logs.
   - Rationale: Firebase Storage download URLs can contain token-bearing query strings.
   - Alternative considered: log only the host/path. Even path-only logs can expose user IDs, so metadata such as request ID and byte count is safer.

## Risks / Trade-offs

- Android local development may need HTTP to a LAN backend -> Mitigation: use HTTPS dev tunnel or add a separate debug-only network config in a future change.
- Backend admin endpoints duplicate existing frontend logic -> Mitigation: implement endpoints narrowly and keep frontend methods as thin API clients.
- Existing admin UI assumptions may depend on direct Firestore writes -> Mitigation: preserve method signatures in `ApiService` while changing internals.
- Migration scripts become less convenient -> Mitigation: fail fast with clear messages naming required environment variables.
- Audit behavior must remain consistent -> Mitigation: backend time-record edit endpoint writes the same audit fields currently written by the frontend transaction.

## Migration Plan

1. Update API transport configuration and Android manifest.
2. Update migration script credential handling and docs.
3. Remove sensitive audio URL logs.
4. Add backend admin mutation endpoints.
5. Update frontend admin service methods to call backend endpoints.
6. Validate with OpenSpec, Python compile, Flutter analysis, and targeted manual smoke checks for admin updates.

## Open Questions

- Should local Android debug builds have a separate cleartext exception for emulator or LAN testing?
- Should all admin Firestore reads also move to backend in a follow-up change?
- Should audio URLs be replaced with short-lived backend download endpoints in a later hardening pass?
