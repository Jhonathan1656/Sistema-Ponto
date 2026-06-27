## Why

The project should remove avoidable security risk around transport, default credentials, sensitive logging, and client-side administrative writes. Firebase rules are already considered well-defined, but moving privileged writes behind backend endpoints gives the system a stronger server-side audit and authorization boundary.

## What Changes

- Enforce HTTPS-only production API access in the Flutter app and disable Android cleartext traffic for release use.
- Remove insecure hardcoded migration passwords and require migration credentials from environment variables or explicit operator input.
- Stop logging Firebase Storage download URLs or other audio URLs that may contain access tokens.
- Move administrative user updates and time-record edits from direct frontend Firestore writes to authenticated backend endpoints.
- Keep Firebase client reads and non-privileged user flows where appropriate, but make privileged mutations pass through backend authorization and audit logic.

## Capabilities

### New Capabilities
- `secure-api-transport`: Production clients must use HTTPS for backend API calls and avoid cleartext fallback.
- `secure-migration-credentials`: Migration scripts must not contain reusable default admin or user passwords.
- `sensitive-url-logging`: The app must not print sensitive storage URLs or token-bearing links to logs.
- `backend-admin-mutations`: Administrative user/profile and time-record mutations must be performed through backend endpoints.

### Modified Capabilities

None.

## Impact

- Frontend: `ponto-system/frontend/lib/services/app_config.dart`, `ponto-system/frontend/android/app/src/main/AndroidManifest.xml`, `ponto-system/frontend/lib/services/api_service.dart`, and admin screens/services that call admin mutation methods.
- Backend: `ponto-system/backend/main.py` for new admin mutation endpoints and audit-preserving behavior.
- Migration: `ponto-system/migration/migrate_from_appsheet.py`.
- Documentation may need small updates describing required migration environment variables and HTTPS-only production behavior.
