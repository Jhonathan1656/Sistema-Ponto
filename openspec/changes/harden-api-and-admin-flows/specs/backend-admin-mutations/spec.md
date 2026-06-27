## ADDED Requirements

### Requirement: Admin user updates go through backend authorization
The system SHALL perform administrative user profile, role, job title, CPF, email, and daily-hours updates through an authenticated backend endpoint.

#### Scenario: Admin updates a user profile
- **WHEN** an authenticated admin submits a user update from the frontend
- **THEN** the frontend sends the mutation to the backend with a Firebase Bearer token
- **AND** the backend validates admin authorization before writing to Firestore

#### Scenario: Non-admin attempts a user update
- **WHEN** a non-admin authenticated user calls the admin user update endpoint
- **THEN** the backend rejects the request with an authorization error

### Requirement: Admin time-record edits go through backend authorization
The system SHALL perform administrative time-record timestamp and notes edits through an authenticated backend endpoint that writes an audit record.

#### Scenario: Admin edits a time record
- **WHEN** an authenticated admin edits a time record
- **THEN** the backend updates the record and creates a corresponding audit entry

#### Scenario: Non-admin attempts a time-record edit
- **WHEN** a non-admin authenticated user calls the admin time-record edit endpoint
- **THEN** the backend rejects the request with an authorization error

### Requirement: Frontend admin mutation methods are thin API clients
Frontend admin mutation methods SHALL call backend endpoints for privileged writes rather than directly updating Firestore collections.

#### Scenario: Admin service updates user role
- **WHEN** `ApiService.updateUserAdmin` is called
- **THEN** it performs an authenticated backend request instead of a direct Firestore document update

#### Scenario: Admin service edits time record
- **WHEN** `ApiService.updateTimeRecordAdmin` is called
- **THEN** it performs an authenticated backend request instead of a direct Firestore transaction
