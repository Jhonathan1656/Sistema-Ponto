## ADDED Requirements

### Requirement: Production API calls use HTTPS
The Flutter app SHALL use HTTPS for production backend API endpoints and MUST NOT include an HTTP fallback for the production domain.

#### Scenario: Android app uses default production backend URLs
- **WHEN** the Android app runs without an explicit `API_BASE_URL`
- **THEN** the configured production backend URLs use `https://` only

#### Scenario: Backend URL override is provided
- **WHEN** a developer provides `API_BASE_URL`
- **THEN** the app uses that explicit value for the backend endpoint

### Requirement: Android cleartext traffic is disabled
The Android application manifest SHALL NOT allow cleartext traffic for the main app configuration.

#### Scenario: Release manifest is inspected
- **WHEN** the Android manifest is reviewed
- **THEN** cleartext traffic is disabled or absent for the application
