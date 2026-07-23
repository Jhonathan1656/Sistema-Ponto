## ADDED Requirements

### Requirement: Effective intern schedule
The system SHALL resolve an intern's effective schedule from a complete enabled user override or the current global intern schedule.

#### Scenario: Intern has no override
- **WHEN** an intern opens the point screen
- **THEN** the system uses the global schedule
- **AND** the default values are 13:30-19:30, start window 13:25-19:25, and overtime threshold 19:35

#### Scenario: Intern has an enabled override
- **WHEN** an administrator enabled a complete schedule override for that intern
- **THEN** all start limits, overtime prompts, scheduled checkout, and notifications use the override

### Requirement: Start-window enforcement
The system SHALL create an intern check-in immediately only from Monday through Friday when the start timestamp is inside the inclusive effective start window, or when a matching approval authorizes it.

#### Scenario: Start inside window
- **WHEN** an intern starts at or after 13:25 and at or before 19:25 under the default schedule
- **THEN** the check-in is created immediately

#### Scenario: Start outside window
- **WHEN** an intern attempts to start outside the effective start window
- **THEN** no check-in is created
- **AND** the app offers to request manager authorization or cancel

#### Scenario: Start during the weekend
- **WHEN** an intern attempts to start on Saturday or Sunday
- **THEN** no check-in is created, even when the time is inside the effective start window
- **AND** the app offers to request manager authorization or cancel

### Requirement: Overtime decision screen
The system SHALL block the intern point screen after the effective overtime threshold when a shift remains open without overtime approval.

#### Scenario: Open shift after threshold
- **WHEN** current time is at or after 19:35 under the default schedule and the intern has an open shift
- **THEN** the point screen is visually gray and normal actions are blocked
- **AND** the app offers to request continuation or close at 19:30

#### Scenario: Intern closes at scheduled end
- **WHEN** the intern selects scheduled-end checkout
- **THEN** the system creates check-out at the effective shift end for that shift date

#### Scenario: Overtime is approved
- **WHEN** a manager approves the continuation request
- **THEN** the screen unlocks
- **AND** work is counted through the actual later checkout
