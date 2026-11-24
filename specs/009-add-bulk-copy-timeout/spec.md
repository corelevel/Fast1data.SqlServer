# Feature Specification: Per-Table Bulk Copy Timeout

**Feature Branch**: `dev` (existing branch; no branch-creation hook configured)

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "Add BulkCopyTimeout to dbo.SourceTable with a default of 30 seconds, allow zero for unlimited waiting, reject negative values, apply the setting to all three archiving bulk-copy operations, preserve query timeout behavior, and require manual preparation of existing installations."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set a time limit for each source table (Priority: P1)

As an archiving administrator, I can configure how long bulk copying may wait for each source table so that larger transfers can use an appropriate limit without changing unrelated tables or query timeouts.

**Why this priority**: Consistent use of a table's configured timeout across every copy stage is the central behavior requested.

**Independent Test**: Configure two tables with different positive limits, such as 60 and 120 seconds. Exercise source-key copying, destination-key copying, and archive-data copying for each table and verify that each stage uses its table's value before writing. Separately verify an operation exceeding its configured limit reports a timeout through the existing failure path.

**Acceptance Scenarios**:

1. **Given** a source table configured with 120 seconds, **When** any of its three bulk-copy operations starts writing, **Then** that operation uses a 120-second timeout.
2. **Given** tables configured with 60 and 120 seconds respectively, **When** each is archived, **Then** all copy operations use their own table's limit without inheriting the other table's value.
3. **Given** a positive timeout and a copy operation that exceeds it, **When** the timeout occurs, **Then** failure is surfaced through existing archiving failure behavior and incomplete work is not recorded as completed.
4. **Given** a bulk-copy timeout different from the connection string's `Command Timeout`, **When** ordinary queries execute, **Then** they retain existing timeout behavior, including the connection string setting where already applicable.

---

### User Story 2 - Keep the default or explicitly wait without a limit (Priority: P1)

As an archiving administrator, I can retain the existing 30-second bulk-copy limit by omitting the new setting, or explicitly choose unlimited bulk-copy waiting for a source table that requires it.

**Why this priority**: The default preserves existing behavior, while zero must remain a distinct and intentional choice.

**Independent Test**: On a new installation, create a source-table configuration without specifying the setting and confirm a stored value of 30. Verify all three copy stages with the default and an explicit zero, including a controlled copy that can wait beyond 30 seconds when unlimited waiting is selected.

**Acceptance Scenarios**:

1. **Given** a new installation, **When** a source-table configuration is inserted without a timeout value, **Then** its timeout is 30 seconds and all three copy stages use that value.
2. **Given** a source table configured with zero, **When** any of its three bulk-copy operations starts writing, **Then** it has no bulk-copy time limit; zero is not replaced by 30.
3. **Given** a source table configured with zero, **When** copying waits longer than 30 seconds, **Then** the bulk-copy timeout alone does not stop it, while ordinary queries retain their existing limits.

---

### User Story 3 - Prepare an existing installation before upgrading (Priority: P1)

As an administrator of an existing installation, I can follow documented manual preparation steps so that all existing source-table configurations retain a 30-second bulk-copy timeout when the changed module is first run.

**Why this priority**: Rerunning setup does not change existing tables, so clear preparation requirements are necessary for a usable upgrade.

**Independent Test**: Review the archiving guide and rehearse its manual preparation on an existing test installation. Confirm rerunning table setup alone does not add the column, all existing rows receive 30, future inserts default to 30, and prepared metadata supplies the setting before the changed module runs.

**Acceptance Scenarios**:

1. **Given** an existing `dbo.SourceTable` lacking the setting, **When** table setup is rerun, **Then** the table remains unchanged and the missing column is not added automatically.
2. **Given** an administrator following upgrade guidance, **When** manual preparation is completed before running the changed module, **Then** the column and validation exist, all preexisting rows have 30, future omitted values default to 30, and `dbo.stp_GetSourceTable` returns the setting.
3. **Given** the archiving guide, **When** an administrator checks the setting and upgrade requirements, **Then** they can identify the default, units, positive and zero semantics, negative rejection, three affected operations, unchanged query timeout behavior, and required preparation order.

---

### User Story 4 - Reject invalid timeout configuration (Priority: P2)

As an archiving administrator, I receive a configuration error when attempting to store a negative or explicitly null timeout so that stored settings always have valid, defined behavior.

**Why this priority**: Validation at the configuration boundary prevents invalid values from reaching archiving operations.

**Independent Test**: In an explicitly selected test database, attempt inserts and updates with negative values and explicit nulls. Confirm rejection, preservation of prior valid values after failed updates, and acceptance of zero and positive integers.

**Acceptance Scenarios**:

1. **Given** a configuration insert or update with a negative timeout, **When** submitted, **Then** the database check constraint rejects it.
2. **Given** an explicitly null timeout, **When** a configuration insert or update is submitted, **Then** it is rejected rather than stored or interpreted as unlimited waiting.
3. **Given** zero or a positive integer within the supported integer range, **When** saved, **Then** it is accepted and read back unchanged.
4. **Given** an existing valid timeout, **When** an invalid update is rejected, **Then** the prior valid value remains stored.

### Edge Cases

- Omitted values on insert use 30; explicit zero remains zero; explicit null is rejected.
- Negative values are rejected on inserts and updates, including direct configuration edits outside the module.
- Zero and the largest supported positive integer, 2,147,483,647, remain valid configuration values and are read without changing their meaning.
- Different tables in the same group retain independent settings.
- A copy stage skipped by the existing workflow need not run solely to apply a timeout; whenever it runs, it uses the configured value.
- An ordinary query may still time out when bulk copying allows unlimited waiting; the setting does not remove query limits or prevent other failures.
- Interrupted or timed-out copies retain existing failure reporting and resumability rules; this feature introduces no new retry behavior.
- An installation without the manually added column or updated metadata procedure is not prepared to run the changed module; automatic repair and compatibility fallback are outside scope.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each source-table configuration MUST persist `BulkCopyTimeout` as a required integer number of seconds. Omitted values on future inserts MUST default to 30, preserving the current bulk-copy timeout unless explicitly overridden.
- **FR-002**: Zero MUST mean unlimited bulk-copy waiting. Positive values through 2,147,483,647 MUST mean a timeout in seconds. Negative values MUST be rejected by a database check constraint, and explicit nulls MUST be rejected.
- **FR-003**: Each table's value MUST apply to all three of its archiving bulk-copy operations: source-key copying, destination-key copying, and archive-data copying. It MUST take effect before each operation starts writing, including when zero.
- **FR-004**: Timeout configuration MUST remain independent for each source table, including tables within one archiving group.
- **FR-005**: Ordinary SQL queries MUST retain their existing timeout behavior, including the connection string's `Command Timeout` where already applicable. Bulk-copy timeout configuration MUST NOT change query timeouts.
- **FR-006**: Archiving metadata MUST expose the configured value and preserve it unchanged through reading and the typed table representation to the copy operations.
- **FR-007**: Fresh installation setup MUST create the setting, default, and validation. Rerunning table setup against an existing `dbo.SourceTable` MUST retain its create-only behavior and MUST NOT add the column or alter existing rows.
- **FR-008**: No migration scripts or automatic alteration of existing tables MUST be introduced. Existing installations MUST be prepared manually before the changed module runs: add the required column and validation, populate every preexisting row with 30, establish a default of 30 for future inserts, and update `dbo.stp_GetSourceTable` to return the setting.
- **FR-009**: `Fast1Archiving.md` MUST document units, default, valid values, the three affected operations, unchanged query timeout behavior, and complete manual preparation requirements. It MUST explicitly explain that rerunning table setup does not add the column to existing tables.
- **FR-010**: Verification MUST cover omitted defaults, positive values, zero, negative inserts and updates, null rejection, independent table settings, metadata propagation, and application to all three copy operations before writing. It MUST also cover unchanged query limits and fresh versus manually prepared existing installations.
- **FR-011**: Bulk-copy failures and interruptions MUST retain existing error visibility and resumability guarantees. Timeout changes MUST NOT change working sets, archiving or purge order, or mark unfinished work complete.

### Key Entities *(include if feature involves data)*

- **Source-table configuration**: Existing per-table archiving configuration, extended with one required timeout value. Each table has an independent setting with a default of 30 seconds.
- **Bulk-copy operation**: One execution of source-key copying, destination-key copying, or archive-data copying, using its owning source table's timeout.
- **Installation preparation state**: Whether configuration storage and metadata include the setting. Fresh installations receive it through setup; existing installations require manual preparation.

### Scope and User-Specified Constraints

These technical boundaries are explicit user requirements retained for planning traceability:

- Add `BulkCopyTimeout` as `int NOT NULL`, with a default of 30 and a check constraint rejecting negative values, to the existing `dbo.SourceTable` creation definition in `Fast1data.SqlServer/schema/archiving/tables.sql`.
- Include the value in `dbo.stp_GetSourceTable`, the metadata reader mapping, and the typed table model.
- Assign the value to `SqlBulkCopy.BulkCopyTimeout` in all three archiving bulk-copy operations before writing.
- Update `Fast1Archiving.md` with setting and manual upgrade guidance. Do not create migration scripts or automatically alter existing tables.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In every default configuration acceptance case, omitted settings resolve to 30 seconds, and manually prepared existing configurations retain the same 30-second limit.
- **SC-002**: For every exercised table, all three copy stages honor its selected default, positive, or unlimited setting, with zero cases of one table inheriting another table's limit.
- **SC-003**: Every negative or explicit-null save attempt is rejected; valid settings survive rejected updates, and all zero and positive boundary acceptance cases succeed.
- **SC-004**: All query-timeout regression scenarios retain their previous results regardless of the bulk-copy timeout selected.
- **SC-005**: An administrator can complete an existing-installation rehearsal using the archiving guide alone, preserve 30 seconds for every preexisting configuration row, and identify all prerequisites before starting archiving. Setup reruns cause zero automatic changes to existing configuration tables.
- **SC-006**: Every exercised copy timeout or interruption surfaces failure without marking incomplete work complete, and existing recovery scenarios remain valid.

## Assumptions

- Administrators already have permissions to manage archiving configuration and perform manual preparation. No new administrative role or public command parameter is introduced.
- Configuration is read through the existing workflow. Applying edits to already running operations is outside scope; an operation uses the value loaded for its table.
- Unlimited waiting applies only to bulk-copy timeout. It does not guarantee completion or override query timeouts, cancellation, connection failures, or other existing failure conditions.
- Existing installations are manually prepared before the changed module runs. Transparent compatibility with an unprepared schema is outside scope.
- Constitution principles I, III, IV, and V apply: preserve resumability, keep database changes explicit, document the changed configuration contract and upgrade order, and verify database-specific behavior against SQL Server where mocks cannot establish correctness.
- Database verification requires an explicitly selected test database and documented setup permissions. Unavailable checks must be recorded as unrun. An explicit release-version decision for this configuration compatibility change is required before release.
