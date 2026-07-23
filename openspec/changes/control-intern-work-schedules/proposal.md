## Why

Interns currently receive only a fixed 19:35 reminder and can create punches at any time. The company needs configurable working-hour boundaries, manager authorization for exceptions, and complete administrative profile editing without relying on client-only checks.

## What Changes

- Introduce a global intern schedule with defaults of 13:30-19:30, allowed start window 13:25-19:25, and overtime decision threshold 19:35.
- Allow a per-user schedule override while preserving the global defaults for all other interns.
- Block an out-of-window intern start and offer either an audited manager authorization request or cancellation.
- Block the intern home screen after the overtime threshold while a shift is open and offer either an authorization request to continue or a checkout at the configured shift end.
- Add a manager approval queue with in-app and push notifications, approval/rejection audit data, and automatic creation of the approved start punch.
- Expand admin user editing to cover name, email, CPF, role, job title, daily hours, account state, password reset, and schedule override.
- Route restricted punches, approvals, global settings, and identity updates through authenticated backend endpoints.

## Capabilities

### New Capabilities

- `intern-work-schedule`: Resolve and enforce global or per-user intern schedules.
- `schedule-approval`: Request, notify, approve, reject, and audit out-of-window work.
- `complete-user-administration`: Administrators can edit all mutable registration/profile fields and reset credentials safely.

### Modified Capabilities

- `backend-admin-mutations`: User e-mail, password, enabled state, and schedule overrides are also managed by the backend.

## Impact

- Backend: new schedule and approval request models/endpoints, server-authoritative punch creation, Firebase Auth profile updates, notifications, and audits.
- Flutter: schedule-aware home screen, blocked overtime state, exception request dialogs, manager approval tab, global schedule editor, and expanded user edit dialog.
- Firestore: `work_schedule_settings`, `work_schedule_approval_requests`, notification records, and additional user schedule fields.
- Operations: Firebase Admin credentials are required in production for approval writes, Auth changes, and push delivery.
