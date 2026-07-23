## ADDED Requirements

### Requirement: Audited schedule authorization requests
The system SHALL persist each out-of-window start or overtime continuation request with requester, effective schedule snapshot, attempted timestamp, status, and decision audit fields.

#### Scenario: Intern requests an exception
- **WHEN** an intern confirms an authorization request
- **THEN** one pending request is persisted
- **AND** all managers and administrators receive an in-app notification and a push attempt

#### Scenario: Intern taps repeatedly
- **WHEN** an equivalent pending request already exists
- **THEN** the system returns the existing request without creating duplicate notifications

### Requirement: Manager decision
Managers and administrators SHALL be able to approve or reject pending schedule requests.

#### Scenario: Manager approves a blocked start
- **WHEN** a manager approves an out-of-window start
- **THEN** the system creates one linked check-in at the original attempted timestamp
- **AND** the intern is notified

#### Scenario: Manager rejects a request
- **WHEN** a manager rejects a pending request
- **THEN** no unauthorized start record is created
- **AND** the intern is notified of the rejection

#### Scenario: Unauthorized user decides
- **WHEN** an employee or intern calls a decision endpoint
- **THEN** the backend rejects the operation
