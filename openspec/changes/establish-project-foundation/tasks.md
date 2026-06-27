## 1. Repository Hygiene

- [ ] 1.1 Review ignored and tracked files for backend virtual environments, caches, local databases, Flutter build output, IDE files, and generated platform artifacts.
- [ ] 1.2 Update root `.gitignore` so common backend, Flutter, Android, iOS, macOS, Windows, and local environment artifacts are excluded consistently.
- [ ] 1.3 Confirm source files, dependency manifests, dependency lockfiles, deployment files, and OpenSpec artifacts remain trackable.
- [ ] 1.4 Run `git status --ignored --short` and verify that noisy generated files are ignored while intended source files remain visible.

## 2. Runtime Configuration Documentation

- [ ] 2.1 Document backend environment variables for secrets, database path, CORS origins, API docs exposure, Firebase, email, shared access, and ZapSign.
- [ ] 2.2 Document frontend API endpoint configuration using `API_BASE_URL` and platform defaults.
- [ ] 2.3 Update quick-start or deploy documentation so local development and production configuration are clearly separated.

## 3. Architecture Baseline

- [ ] 3.1 Document current backend responsibilities: access gate, Firebase authentication, exports, signature documents, notifications, webhooks, and admin actions.
- [ ] 3.2 Document current frontend integration pattern: screens depend on service classes for backend/Firebase communication.
- [ ] 3.3 Identify a follow-up OpenSpec change for backend modularization if the monolithic `main.py` remains hard to maintain.

## 4. Validation

- [ ] 4.1 Run OpenSpec validation for `establish-project-foundation`.
- [ ] 4.2 Run lightweight project checks that are available locally, such as Python compile checks and Flutter analysis when dependencies are installed.
- [ ] 4.3 Archive the completed OpenSpec change so the new capabilities become baseline specs.
