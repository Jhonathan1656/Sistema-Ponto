## ADDED Requirements

### Requirement: Backend exposes domain responsibilities through stable API boundaries
The backend SHALL keep authentication, exports, signature documents, notifications, access gating, and administrative actions as identifiable responsibilities with stable HTTP API contracts.

#### Scenario: New backend feature is proposed
- **WHEN** a future change adds or modifies a backend feature
- **THEN** the proposal identifies the affected API contract and domain responsibility

### Requirement: Frontend API integration remains centralized
The frontend SHALL route backend HTTP communication through service classes rather than scattering raw backend calls across screens.

#### Scenario: Backend endpoint changes
- **WHEN** a backend endpoint path or request format changes
- **THEN** the corresponding frontend update is made in the API/service layer before screens rely on it

### Requirement: Authentication and authorization contracts are explicit
The system SHALL treat Firebase identity, role-based authorization, admin actions, and shared access gating as explicit security contracts.

#### Scenario: Admin-only endpoint is called by a non-admin user
- **WHEN** a non-admin authenticated user calls an admin-only backend action
- **THEN** the backend rejects the request with an authorization error

### Requirement: Future structural refactors preserve behavior
The project SHALL allow incremental refactoring of backend and frontend modules only when existing user-facing behavior and API contracts remain preserved or are explicitly changed by spec.

#### Scenario: Backend code is split into modules
- **WHEN** backend code is reorganized into separate modules
- **THEN** existing documented endpoints and behaviors remain compatible unless a change proposal states otherwise
