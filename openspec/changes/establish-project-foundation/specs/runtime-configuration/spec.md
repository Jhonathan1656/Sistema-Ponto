## ADDED Requirements

### Requirement: Backend uses environment-driven operational configuration
The backend SHALL read operational secrets, integration tokens, database paths, API documentation exposure, allowed origins, and shared access tokens from environment variables.

#### Scenario: Backend starts without production secrets
- **WHEN** the backend starts in local development without production secrets
- **THEN** it avoids using known insecure production placeholders as persistent secrets

#### Scenario: Backend runs in production
- **WHEN** production deployment provides required environment variables
- **THEN** backend behavior uses those configured values rather than hardcoded development-only values

### Requirement: Frontend backend URL is build/runtime configurable
The Flutter frontend SHALL determine backend API endpoints from build-time or platform-aware configuration rather than requiring source edits for each environment.

#### Scenario: Web app is served behind the backend proxy
- **WHEN** the app runs on web without an explicit API base URL
- **THEN** it targets the current origin API path

#### Scenario: Mobile app targets production API
- **WHEN** the app runs on Android or another mobile platform without a development override
- **THEN** it uses the configured production backend endpoint

### Requirement: Configuration documentation is complete
The project SHALL document the required environment variables and build-time configuration values for local development and deployment.

#### Scenario: New developer starts the project
- **WHEN** a new developer follows the quick-start documentation
- **THEN** they can identify which values are required, which are optional, and which defaults are safe only for local development
