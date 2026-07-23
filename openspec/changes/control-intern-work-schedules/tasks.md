## 1. Backend Schedule Model

- [x] 1.1 Add validated time/schedule request models and default schedule resolution.
- [x] 1.2 Add global schedule read/update endpoints and audit changes.
- [x] 1.3 Add effective per-user schedule resolution and response endpoint.

## 2. Restricted Punches and Approvals

- [x] 2.1 Add server-authoritative intern punch endpoint with start-window validation.
- [x] 2.2 Add idempotent start/overtime approval request creation.
- [x] 2.3 Add manager queue/list, approve, and reject endpoints.
- [x] 2.4 Create approved start records at the attempted timestamp and support scheduled-end checkout.
- [x] 2.5 Add persistent notifications, push attempts, and audit metadata.

## 3. Complete User Administration

- [x] 3.1 Expand the backend user update model for account state, password reset, and schedule override.
- [x] 3.2 Synchronize e-mail/password/disabled state with Firebase Authentication.
- [x] 3.3 Extend audit data without logging password contents.

## 4. Flutter Employee Experience

- [x] 4.1 Add schedule and approval API client methods and cache effective schedules.
- [x] 4.2 Block out-of-window intern starts with request/cancel choices.
- [x] 4.3 Replace the fixed 19:35 reminder with a gray overtime decision screen.
- [x] 4.4 Allow scheduled-end checkout and refresh automatically after a manager decision.
- [x] 4.5 Require manager authorization for intern starts on Saturday and Sunday.
- [x] 4.6 Do not treat a cached profile as an authenticated Firebase session.

## 5. Flutter Manager/Admin Experience

- [x] 5.1 Add an approval queue tab for managers and administrators.
- [x] 5.2 Add global intern schedule configuration for administrators.
- [x] 5.3 Expand user editing for e-mail, CPF, role, function, daily hours, account state, password reset, and per-user schedule override.

## 6. Validation and Delivery

- [ ] 6.1 Add backend tests for schedule boundaries, idempotency, approval, and authorization.
- [x] 6.2 Run Python compile/tests and Flutter format/analyze/tests.
- [x] 6.3 Build the web admin and release APK.
- [ ] 6.4 Document the APK path and Firebase Admin deployment prerequisite.
- [x] 6.5 Add backend and Flutter tests for weekend start restrictions.
