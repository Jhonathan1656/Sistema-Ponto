## ADDED Requirements

### Requirement: Migration credentials are operator-provided
Migration scripts SHALL obtain admin credentials and any default migrated-user password from environment variables or explicit operator input, not hardcoded reusable defaults.

#### Scenario: Migration runs without required credentials
- **WHEN** a migration script starts without required credential values
- **THEN** it fails before creating users and reports which configuration is missing

#### Scenario: Migration creates imported users
- **WHEN** imported users are created
- **THEN** their initial password comes from operator-provided configuration rather than a repository default

### Requirement: Migration output avoids password disclosure
Migration scripts SHALL NOT print plaintext passwords or access tokens to stdout/stderr.

#### Scenario: Authentication fails during migration
- **WHEN** the migration script fails to authenticate
- **THEN** the output does not include submitted passwords or bearer tokens
