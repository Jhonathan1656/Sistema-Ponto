## 1. Secure API Transport

- [ ] 1.1 Remove the production HTTP backend fallback from `AppConfig.backendUrls`.
- [ ] 1.2 Disable or remove `android:usesCleartextTraffic="true"` from the Android main manifest.
- [ ] 1.3 Search the frontend for production `http://` backend URLs and replace them with HTTPS or local-only configuration.

## 2. Secure Migration Credentials

- [ ] 2.1 Replace hardcoded `ADMIN_EMAIL`, `ADMIN_PASSWORD`, and migrated-user default password values with environment-variable loading.
- [ ] 2.2 Fail fast with clear missing-configuration errors when migration credentials are absent.
- [ ] 2.3 Ensure migration output does not print plaintext passwords or bearer tokens.

## 3. Sensitive URL Logging

- [ ] 3.1 Remove debug output that prints audio download URLs.
- [ ] 3.2 Replace sensitive URL logs with safe metadata such as request ID, upload status, and byte count.
- [ ] 3.3 Search frontend logs for signed document URLs, storage URLs, token query strings, and similar sensitive links.

## 4. Backend Admin Mutations

- [ ] 4.1 Add a backend request model and endpoint for admin user updates.
- [ ] 4.2 Add a backend request model and endpoint for admin time-record edits.
- [ ] 4.3 Preserve time-record audit creation when edits move from frontend transaction to backend endpoint.
- [ ] 4.4 Ensure both endpoints use `require_admin_user` and return appropriate 403 errors for non-admin users.

## 5. Frontend Admin API Calls

- [ ] 5.1 Update `ApiService.updateUserAdmin` to call the backend endpoint with a Firebase Bearer token.
- [ ] 5.2 Update `ApiService.updateTimeRecordAdmin` to call the backend endpoint with a Firebase Bearer token.
- [ ] 5.3 Preserve existing admin screen method signatures and user-facing behavior.

## 6. Validation

- [ ] 6.1 Run `openspec validate harden-api-and-admin-flows`.
- [ ] 6.2 Run Python compile checks for the backend.
- [ ] 6.3 Run Flutter analysis for the frontend when dependencies are available.
- [ ] 6.4 Manually smoke-check admin user update, admin time-record edit, and audio upload logging behavior.
