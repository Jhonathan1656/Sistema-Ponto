## Context

The repository contains a FastAPI backend, a Flutter frontend, deployment files, migration scripts, and now OpenSpec planning artifacts. The backend currently concentrates many concerns in `main.py`, including access gate pages, export generation, Firebase authentication, ZapSign document signing, notifications, and SQLite-backed document metadata. The frontend already has separate screens/services and uses Firebase plus backend API calls.

OpenSpec currently has no baseline specs, so future changes do not yet have a stable reference for what the project considers correct behavior. The first foundation change should document contracts and clean up development workflow without changing product behavior.

## Goals / Non-Goals

**Goals:**
- Establish baseline specs for repository hygiene, runtime configuration, and project architecture.
- Make generated/local artifacts less likely to appear in searches, commits, or reviews.
- Clarify which configuration values must come from environment/build-time configuration.
- Create a low-risk task list that can be implemented incrementally.

**Non-Goals:**
- Redesign the UI.
- Replace Firebase, SQLite, ZapSign, or FastAPI.
- Change employee time calculation rules.
- Perform a full backend modularization in one large rewrite.
- Add new end-user features.

## Decisions

1. Treat this as a foundation proposal, not a feature proposal.
   - Rationale: the highest-leverage next step is making future work safer and easier to specify.
   - Alternative considered: propose a new feature such as advanced reports. That can wait until the project contracts are documented.

2. Create baseline specs before changing implementation.
   - Rationale: OpenSpec becomes useful when it records expected behavior, not only planned code edits.
   - Alternative considered: change `.gitignore` and docs immediately. That would help, but would miss the chance to define durable project rules.

3. Keep implementation incremental.
   - Rationale: the backend touches auth, exports, documents, webhooks, email, and notifications. A big rewrite would be risky.
   - Alternative considered: split `main.py` into many modules immediately. That should be done later under a focused architecture change.

4. Prefer environment/build-time configuration over hardcoded operational values.
   - Rationale: local development, production, and mobile/web builds need different URLs, secrets, and integration tokens.
   - Alternative considered: maintain current defaults in code. Defaults are convenient locally but risky when they include production endpoints or secret-like placeholders.

## Risks / Trade-offs

- Spec drift -> Mitigation: validate OpenSpec changes before implementation and archive completed changes into baseline specs.
- Over-documentation -> Mitigation: keep specs focused on observable behavior and repository rules, not implementation trivia.
- Accidental removal of needed generated files -> Mitigation: review tracked files before changing ignore rules; only remove files that are generated or documented as local.
- Configuration breakage -> Mitigation: document required variables and preserve safe local defaults where appropriate.

## Migration Plan

1. Review and approve this OpenSpec change.
2. Implement hygiene changes first because they are easiest to validate.
3. Document runtime configuration and update quick-start/deploy docs.
4. Add lightweight tests or validation checks for backend startup/config where practical.
5. Archive the change so these specs become the project baseline.

Rollback is straightforward: revert the implementation commit or keep the specs as planning artifacts without applying code changes.

## Open Questions

- Should backend API docs remain disabled by default in all production deployments, or should admin-only docs be supported later?
- Should local development use SQLite permanently, or should production target a managed database in a future proposal?
- Should the backend be modularized by domain next, after this foundation work is accepted?
