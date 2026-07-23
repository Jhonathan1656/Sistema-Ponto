## ADDED Requirements

### Requirement: Complete mutable user editing
An administrator SHALL be able to edit the user's name, e-mail, CPF, role, job title, daily hours, enabled state, and effective schedule override.

#### Scenario: Admin changes profile and schedule
- **WHEN** an administrator saves valid profile values and a schedule override
- **THEN** Firestore stores the profile and complete override
- **AND** subsequent schedule checks use the new values

### Requirement: Safe credential administration
An administrator SHALL be able to replace a user's password without retrieving or displaying the existing password.

#### Scenario: Admin sets a new password
- **WHEN** an administrator supplies a valid new password
- **THEN** Firebase Authentication replaces the credential
- **AND** no password value is stored in Firestore, logs, or audit documents

#### Scenario: Password field is blank
- **WHEN** an administrator saves the user with no new password
- **THEN** the current credential remains unchanged

### Requirement: Auth and profile identity synchronization
The system SHALL synchronize administrative e-mail and account-state changes between Firebase Authentication and Firestore through the backend.

#### Scenario: Admin changes e-mail
- **WHEN** a valid unused e-mail is saved
- **THEN** Firebase Authentication and the Firestore user profile contain the new e-mail

#### Scenario: Non-admin attempts identity editing
- **WHEN** a manager or other non-admin calls the identity update endpoint
- **THEN** the backend rejects the mutation
