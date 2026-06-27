## Why

The project already has meaningful product surface across time tracking, admin workflows, document signing, notifications, and exports, but OpenSpec has no baseline specs yet. Establishing foundation specs now will make future changes safer, easier to review, and less dependent on reading the whole FastAPI/Flutter codebase.

## What Changes

- Add baseline OpenSpec capabilities that describe repository hygiene, runtime configuration, and core project contracts.
- Define how generated/local files should be kept out of version control so searches, reviews, and commits stay focused.
- Define required runtime configuration behavior for backend secrets, API URLs, docs exposure, Firebase, email, database path, and ZapSign integration.
- Define initial architectural expectations for the FastAPI backend and Flutter frontend so future feature proposals have stable boundaries.
- No production behavior changes are required by this proposal by itself; implementation should be incremental and low risk.

## Capabilities

### New Capabilities
- `repository-hygiene`: Rules for tracked source files, ignored generated artifacts, dependency lockfiles, and local environment files.
- `runtime-configuration`: Requirements for environment-driven configuration across backend and frontend.
- `project-architecture`: Baseline contracts for backend/frontend responsibilities, API integration, authentication, and feature organization.

### Modified Capabilities

None.

## Impact

- Affected planning artifacts: `openspec/specs/**`, `openspec/changes/**`.
- Likely affected repo files during implementation: `.gitignore`, `README.md`, `QUICK_START.md`, `DEPLOY.md`, `ponto-system/backend/main.py`, `ponto-system/backend/requirements.txt`, `ponto-system/frontend/lib/services/app_config.dart`, and Flutter build/config files.
- No database migration is expected for this foundation change.
