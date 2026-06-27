## ADDED Requirements

### Requirement: Generated artifacts stay out of version control
The repository SHALL exclude generated build output, virtual environments, caches, local databases, IDE metadata, and platform-generated files from normal source control workflows.

#### Scenario: Developer checks repository status after a local build
- **WHEN** a developer runs backend or Flutter build commands locally
- **THEN** generated directories and local machine artifacts do not appear as untracked source changes intended for commit

#### Scenario: Developer searches project source
- **WHEN** a developer searches source files for implementation details
- **THEN** vendored virtual environment packages and build outputs are not included in normal source search scope

### Requirement: Source and lockfiles remain trackable
The repository SHALL continue tracking source code, deployment files, OpenSpec artifacts, dependency manifests, and dependency lockfiles that are required for reproducible development.

#### Scenario: Dependency changes are committed
- **WHEN** a dependency is added or updated intentionally
- **THEN** the relevant manifest and lockfile changes are visible for review

### Requirement: Local secrets are not committed
The repository SHALL ignore local environment files, local databases, and secret-bearing generated files.

#### Scenario: Developer configures local secrets
- **WHEN** a developer creates local `.env` files or local database files
- **THEN** those files are excluded from commits by default
