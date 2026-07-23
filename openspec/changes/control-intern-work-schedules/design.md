## Context

Time records are currently written directly by the Flutter client and may be queued offline. The 19:35 intern behavior is a hardcoded local reminder. User edits currently update only a subset of Firestore fields and do not synchronize Firebase Authentication. A client-only restriction would be bypassable and could accept an unauthorized offline record later.

## Goals / Non-Goals

**Goals:**
- Make intern schedule enforcement authoritative on the backend.
- Support one global schedule and optional complete per-user overrides.
- Preserve the attempted timestamp when a manager approves an out-of-window start.
- Give managers a clear approval queue and notify relevant parties.
- Let administrators edit all mutable user registration/profile data and reset passwords.
- Record who requested and who decided each exception.

**Non-Goals:**
- Display or recover an existing password.
- Allow editing immutable Firebase UID or creation/audit timestamps.
- Apply intern restrictions to normal employees, managers, or administrators.
- Make authorization requests work offline.

## Decisions

1. Store global settings in `work_schedule_settings/intern_default`.
   - Defaults: `shift_start=13:30`, `shift_end=19:30`, `start_allowed_from=13:25`, `start_allowed_until=19:25`, `overtime_prompt_after=19:35`, `timezone=America/Sao_Paulo`.

2. Store a full optional override in the user document.
   - `work_schedule_override_enabled` chooses between global settings and the user's `work_schedule_override` map.
   - A full snapshot avoids partially inherited schedules changing unexpectedly when the global schedule changes.

3. Enforce intern starts through a backend endpoint.
   - An in-window start creates the time record immediately.
   - An out-of-window start returns `approval_required`; no time record is created until the request is approved.
   - Approval creates the `check_in` using the original attempted timestamp and links it to the request.

4. Treat 19:35 as a decision threshold, not an automatic checkout.
   - While a shift is open and no overtime approval exists for it, the home screen becomes gray and blocks normal actions.
   - `Continuar trabalhando` opens a pending request. Approval unlocks the shift and permits checkout at the actual time.
   - `Fechar no horario` creates a checkout at the configured shift end.

5. Make requests idempotent.
   - Only one pending request of a given type may exist for the user and shift/day.
   - Repeated taps return the existing request instead of notifying managers multiple times.

6. Notify through persistent in-app data first and FCM second.
   - Manager/user notification documents are created even if push delivery fails.
   - FCM failures do not lose the approval request.

7. Restrict decisions to `admin` and `manager`, and identity edits to `admin`.
   - Managers can decide schedule requests but cannot change identity, role, e-mail, or password.

8. Update Firebase Authentication and Firestore together for identity changes.
   - E-mail, password, and disabled state are updated with Firebase Admin.
   - Password is write-only and omitted when blank.
   - Audit entries list changed field names but never store the password.

## Risks / Trade-offs

- Restricted intern actions require connectivity -> show a clear online-required message and keep ordinary cached viewing available.
- Backend and device clocks may differ -> use the requested timestamp for UX but validate it against bounded server time to prevent forged dates.
- A manager may approve after a long delay -> preserve the attempt time and show it prominently in the queue/audit.
- Firebase Admin may be missing -> endpoints fail clearly; persistent push/identity features require production service-account configuration.
- Existing records lack approval metadata -> treat them as legacy records and enforce rules only on new restricted actions.

## Migration Plan

1. Deploy backend endpoints and global defaults.
2. Deploy web/admin approval and configuration UI.
3. Deploy mobile schedule enforcement and overtime blocker.
4. Verify Firebase Admin credentials and FCM tokens in production.
5. Monitor approval audits and rejected punch attempts.
