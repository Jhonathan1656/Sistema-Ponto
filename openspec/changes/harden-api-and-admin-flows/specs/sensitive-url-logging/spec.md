## ADDED Requirements

### Requirement: Token-bearing URLs are not logged
The frontend SHALL NOT log Firebase Storage download URLs, signed document URLs, audio URLs, or other token-bearing links.

#### Scenario: Audio upload succeeds
- **WHEN** an adjustment audio upload completes
- **THEN** debug output does not include the returned download URL

#### Scenario: Audio upload fails
- **WHEN** an audio upload or fallback fails
- **THEN** debug output may include safe request metadata but not the audio download URL or token query string

### Requirement: Logs use safe metadata
The app SHALL prefer request IDs, byte counts, statuses, and non-sensitive operation names in debug logs.

#### Scenario: Developer diagnoses audio upload
- **WHEN** a developer reads debug logs for an audio upload
- **THEN** they can identify the operation and status without seeing a token-bearing URL
