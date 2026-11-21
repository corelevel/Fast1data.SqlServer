# Feature Specification: Remove the SqlServer Module Dependency

**Feature Branch**: `dev` (existing branch; no branch hook configured)

**Created**: 2026-11-19

**Status**: Draft

**Input**: User description: "Get rid of dependency on SqlServer module. Invoke-Migration and Set-Executed must accept Microsoft.Data.SqlClient.SqlCommand instead of connection string. Invoke-Migration must use Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser to parse T-SQL script and execute batches instead of Invoke-Sqlcmd."

**Additional requirement (2026-11-19)**: "Create a new parameterized function to load the required DLL, like Microsoft.Data.SqlClient.dll, Microsoft.SqlServer.TransactSql.ScriptDom.dll, etc."

**Additional requirement (2026-11-19)**: "Invoke-Migration must create and use a separate connection to the target database."

**Additional requirement (2026-11-19)**: "Modify Invoke-Migration to accept a connection string as a parameter and then open a connection inside the function." This supersedes the earlier `Invoke-Migration -SqlCmd` input and borrowed-command requirements. `Set-Executed -SqlCmd` remains unchanged. This addition updates requirements only; implementation is tracked separately.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run migrations without an extra PowerShell module (Priority: P1)

As an operator, I want to install and use the module without installing the separate SqlServer PowerShell module so that migration automation has fewer setup requirements.

**Why this priority**: Removing this prerequisite is the primary requested outcome and must work in a clean environment.

**Independent Test**: Import a built distribution in a clean supported environment where the SqlServer PowerShell module is absent, then run a representative migration and verify its effects and execution history.

**Acceptance Scenarios**:

1. **Given** the module distribution and its documented prerequisites are present but the SqlServer PowerShell module is absent, **When** an operator imports the module, **Then** import succeeds without attempting to load or install that PowerShell module and the same three public operations are available.
2. **Given** an initialized migration history and valid migration files, **When** the operator invokes the existing public migration command with its existing parameters, **Then** eligible scripts execute and their history is recorded without requiring the removed prerequisite.
3. **Given** a maintainer builds and packages the module for a supported platform, **When** an operator follows the updated installation and migration guidance, **Then** the distribution supplies the required execution and parsing dependencies without a separate SqlServer PowerShell module installation.

---

### User Story 2 - Execute migration batches faithfully (Priority: P1)

As a migration author, I want each script to execute as an ordered sequence of complete batches so that scripts containing batch separators, comments, quoted text, and batch-scoped definitions run correctly.

**Why this priority**: Replacing script execution must preserve script meaning and must never record a partially failed script as completed.

**Independent Test**: Run scripts containing multiple batches, separator-like text in comments and strings, a definition requiring its own batch, a session-local object used across batches, a syntax error, and a later runtime failure. Inspect effects, diagnostics, and history.

**Acceptance Scenarios**:

1. **Given** a valid script containing multiple batches separated by standalone `GO` lines, **When** it executes, **Then** every non-empty batch runs once in source order and the complete script receives one history record only after all batches succeed.
2. **Given** a script contains `GO` within strings or comments and statements spanning several lines, **When** batches are identified, **Then** these constructs retain their original meaning and do not create false batch boundaries.
3. **Given** one batch creates a session-local object or setting needed by a later batch, **When** the later batch executes, **Then** it uses the same database session and can observe the earlier batch's session state.
4. **Given** a script contains a syntax error anywhere in its contents, **When** execution is requested, **Then** parsing fails before any batch from that script executes, the error identifies the script and source location, and no successful history entry is written for that attempt.
5. **Given** a later batch fails during execution, **When** the failure occurs, **Then** remaining batches and later scripts do not execute, the error identifies the failing script and batch, and no successful history entry is written for that attempt. Earlier committed work remains subject to the existing retry contract.
6. **Given** a script is empty or contains only whitespace, comments, or empty batches, **When** it is selected for execution, **Then** no empty database command is sent and the successfully processed script is recorded once.

---

### User Story 3 - Keep history resources reusable and separate from scripts (Priority: P2)

As a maintainer, I want history recording to reuse a caller-owned command while scripts receive the target connection string and own their execution resources, so that script session changes cannot affect history.

**Why this priority**: This contract keeps caller-owned resources reusable and makes the executor responsible for its separate script connection.

**Independent Test**: Supply a connection string to the executor and a separate initialized command to the history writer. Verify session separation, history command reuse/settings, and resource cleanup on success and failure.

**Acceptance Scenarios**:

1. **Given** an initialized history command associated with an open connection, **When** `Set-Executed` runs, **Then** it uses that command's connection, timeout, and assigned transaction unchanged. `Invoke-Migration` independently accepts the connection string under FR-016.
2. **Given** the caller supplies the history command, **When** history recording succeeds or fails, **Then** `Set-Executed` leaves the command and connection open and undisposed; the executor never receives or modifies these resources.
3. **Given** multiple eligible scripts, **When** the public migration command runs, **Then** it passes its original `ConnStr` to each executor invocation, writes history through its own command before the next script, and releases its owned resources on success or failure.
4. **Given** the history command is reused across records, **When** the next history write begins, **Then** previous command text and parameters cannot alter its intended execution and history values remain parameterized. Script commands are independently owned by the executor.
5. **Given** a script succeeds but its history write fails, **When** the failure occurs, **Then** the public operation terminates without executing the next script and reports the failure; retry still requires idempotent scripts because the earlier script may already have taken effect.
6. **Given** preview mode, declined confirmation, or a phase with no eligible scripts, **When** the public operation evaluates the phase, **Then** existing read-only validation and reporting remain available, no script or history mutation occurs, and no mutation command is created solely for execution that will not occur.
7. **Given** a missing history command, missing connection, or closed connection, **When** `Set-Executed` is called, **Then** it fails before database mutation with an actionable error and does not open a replacement connection.

---

### User Story 4 - Load required libraries through one reusable function (Priority: P2)

As a maintainer, I want one parameterized function to load a required bundled library so that adding a dependency does not require another library-specific loading implementation.

**Why this priority**: SqlClient and ScriptDom need the same runtime selection, assembly reuse, and failure reporting; maintaining those behaviors once avoids inconsistent dependency initialization.

**Independent Test**: Call the same function with each required DLL filename in fresh source and packaged processes, repeat the calls, and exercise missing, corrupt, and incompatible dependencies.

**Acceptance Scenarios**:

1. **Given** a supported runtime and its bundled dependencies, **When** the function receives either `Microsoft.Data.SqlClient.dll` or `Microsoft.SqlServer.TransactSql.ScriptDom.dll`, **Then** it loads the requested assembly from the selected distribution's matching runtime folder through the same implementation.
2. **Given** another required managed DLL is included in that bundle, **When** its filename is supplied, **Then** no new library-specific loading function or hardcoded supported-name list is required.
3. **Given** the requested assembly is already loaded, **When** initialization repeats, **Then** the function reuses it and validates any caller-specified required types, including `TSql160Parser` for ScriptDom.
4. **Given** a missing, corrupt, or incompatible dependency, **When** initialization is attempted, **Then** loading terminates with the requested dependency, runtime, expected path, and rebuild guidance, and no usable partial public operations remain.
5. **Given** the existing bootstrap entry points, **When** module and fixture initialization run, **Then** they use the shared parameterized function, required libraries are ready before dependent behavior, and the same three public commands remain exported.

---

### User Story 5 - Isolate each script's database session (Priority: P1)

As an operator, I want each migration script to run through a separate target-database connection so that session changes made by scripts cannot change the history connection or leak into later script files.

**Why this priority**: Connection isolation is explicitly required and changes the executor's resource-ownership contract.

**Independent Test**: Compare script and history session identities; share a temporary object between batches in one file; change database/session settings inside that file; then inspect history and the next script's session. Exercise connection/command creation, open, execution, and cleanup failures.

**Acceptance Scenarios**:

1. **Given** a target connection string, **When** a validated script with executable batches runs, **Then** `Invoke-Migration` creates and opens its own connection using that string, creates its own command, and runs all batches of that file in the same script session.
2. **Given** a script changes database or session settings or creates temporary objects, **When** execution finishes, **Then** the original connection remains unaffected and the next script starts in a separately initialized target session. History remains on the original target connection.
3. **Given** execution succeeds or fails, **When** the helper exits, **Then** it attempts disposal of its own command, connection, and ambient-suppression scope in that order, without touching history resources. Cleanup failures must not hide the primary error.
4. **Given** reading, preflight, or parsing fails, or the script has no executable batches, **When** the helper processes the file, **Then** no script execution connection is opened. Empty-file completion recording remains supported.
5. **Given** a caller has an ambient transaction or a transaction on the history command, **When** script execution runs, **Then** its separate connection remains under the existing ambient-suppression policy and does not use the history transaction; `Set-Executed` retains its existing transaction contract.
6. **Given** the connection string cannot initialize or open the target connection, **When** execution is attempted, **Then** the operation terminates without executing batches on any history connection, without recording completion, and without exposing secrets.

---

### User Story 6 - Invoke a script directly with a connection string (Priority: P1)

As a maintainer, I want `Invoke-Migration` to accept a connection string and open its own connection so that callers do not need to construct or lend it database resources.

**Why this priority**: This explicitly replaces the executor's previously specified input and resource-sharing mechanism while preserving per-file isolation.

**Independent Test**: Invoke the helper using only `-ConnStr` and `-Script`; verify owned connection/command creation, configured target selection, batch execution, failure cleanup, and that the public caller forwards its original connection string.

**Acceptance Scenarios**:

1. **Given** a valid target connection string and migration file, **When** `Invoke-Migration -ConnStr <string> -Script <path>` runs, **Then** neither a caller-supplied command nor an already-open connection is required, and the helper internally opens the specified target connection and creates its command.
2. **Given** the public migration command receives a connection string, **When** it invokes the executor, **Then** it forwards that original string rather than reconstructing it from an opened history connection. History continues to use `Set-Executed -SqlCmd`.
3. **Given** a missing, empty, whitespace-only, or malformed connection string, **When** execution is requested, **Then** it fails actionably without executing batches or writing history and without including the connection string or secrets in contextual diagnostics.
4. **Given** a script requiring multiple batches, **When** it runs with the new interface, **Then** the executor uses one owned command/session with the existing unbounded script timeout, validates final transaction completion, and releases every owned resource before reporting success.

### Edge Cases

- Leading, trailing, and consecutive batch separators must not result in empty commands. Separator-like text inside comments or string literals must remain part of its original batch.
- A definition that must begin a batch must retain its batch boundary. Session-local objects and settings must remain available between batches in the same script.
- A syntax error in a later batch must prevent earlier batches of that script from executing; a runtime error can occur after earlier batches have committed.
- A file read failure or unavailable parser dependency must terminate the affected operation without recording the script as successfully executed.
- A forced rerun that fails must not update the previous history entry. A successful forced rerun must still locate the original stored key and update the normalized script name, checksum, and database UTC timestamp.
- Reusing a history command must not leave stale history values in the next record; script execution uses its own command and parameters.
- Script connection/command creation, opening, and disposal can fail. Every already-created owned resource must still be cleaned up, and history resources must remain untouched.
- A script's `USE`, temporary objects, session settings, and explicit transaction state belong to its execution connection; history must remain unaffected. Target and authentication come from the original supplied connection string, without reconstructing it from an opened connection.
- SQL execution errors must remain the primary failure if resource cleanup also fails. Error reporting must not expose connection strings or credentials.
- Repeated generic loading must not hide incompatible preloaded assemblies or fall back to the source tree when a selected package is missing a requested dependency. A dependency filename must resolve within the selected runtime bundle.
- SQLCMD preprocessing directives, variable substitution, and repeat-count separators such as `GO 3` are outside the supported script contract for this feature. Unsupported constructs must fail clearly before any batch in that script executes rather than be silently ignored or partially interpreted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST no longer declare, import, invoke, or require the SqlServer PowerShell module. All existing public operations MUST remain importable without it, and the migration path MUST contain no `Invoke-Sqlcmd` execution. Acceptance: Story 1, scenarios 1-2.
- **FR-002**: `Set-Executed` MUST require a caller-supplied `Microsoft.Data.SqlClient.SqlCommand`, use its existing open connection, and preserve its timeout and assigned transaction. `Invoke-Migration` MUST instead require the connection string described by FR-016; it MUST NOT require a caller command or open connection. Acceptance: Story 3, scenarios 1 and 7; Story 6, scenario 1.
- **FR-003**: `Set-Executed` MUST NOT allocate replacement SQL resources or close/dispose its supplied command or connection. `Invoke-Migration` MUST own and release its own command and separate connection, without touching history resources. Invalid input MUST fail before database mutation. Acceptance: Story 3, scenarios 1-2 and 7; Story 5, scenario 3; Story 6, scenario 3.
- **FR-004**: `Invoke-Migration` MUST parse the complete script with `Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser` before executing any of its batches. Parsing errors MUST terminate that script without executing any batch and identify the script and source location. Acceptance: Story 2, scenario 4.
- **FR-005**: Script execution MUST follow the parser's batch boundaries and source order, preserve the source meaning of every batch, skip empty batches, and use one executor-owned command and connection for all batches of that file. It MUST NOT mistake comments, string contents, or statement boundaries for batch separators. Acceptance: Story 2, scenarios 1-3 and 6; Story 5, scenario 1.
- **FR-006**: Any script-read, parse, batch-execution, or history-write failure MUST terminate the migration operation before later batches or scripts execute. Execution diagnostics MUST identify the affected script and failing batch where applicable, preserve the underlying error, and omit secrets. Acceptance: Story 2, scenarios 4-5; Story 3, scenario 5; corresponding edge cases.
- **FR-007**: History MUST be written only after every batch in a script succeeds, once per script rather than per batch. New and forced execution MUST preserve existing script identity, SHA-256 checksum, phase, and database UTC timestamp behavior; failed reruns MUST leave the prior history entry unchanged. Empty or comment-only scripts MUST remain successful recorded executions. Acceptance: Story 2, scenarios 1, 4-6; forced-rerun edge case.
- **FR-008**: History values MUST remain parameterized, and command reuse MUST prevent stale command text or parameters from affecting later operations. Acceptance: Story 3, scenario 4.
- **FR-009**: `Invoke-Fast1Migration` MUST retain its public interface, forward its original connection string to `Invoke-Migration`, and supply its owned history command to `Set-Executed`. Each executor invocation MUST own its script command and separate connection. Each owner MUST clean up on success or failure without masking a primary operation error. History MUST remain on its original connection, with no implicit phase-wide transaction. Acceptance: Story 3, scenarios 2-3 and 5; Story 5, scenarios 2-3; Story 6, scenario 2.
- **FR-010**: Existing phase and script order, pre-execution configuration validation, path containment, checksum checks, ignore/force behavior, warning and verbose reporting, and confirmation behavior MUST be preserved. Preview and declined confirmation MUST execute no batches and write no history. Acceptance: Story 1, scenario 2; Story 3, scenarios 3, 5-6; existing migration regression coverage.
- **FR-011**: Build and packaging MUST supply the required parsing dependency and preserve the current supported runtime and platform contracts. Assembly initialization MUST remain owned by the established loaders, and missing dependencies MUST produce actionable errors. Acceptance: Story 1, scenarios 1 and 3; unavailable-dependency edge case.
- **FR-012**: The manifest, public help, installation instructions, migration guidance, and release guidance MUST reflect the removed prerequisite, required bundled dependencies, changed private helper contracts, supported script syntax, and retry limitations. No migration-history schema or public command parameter change is required. Acceptance: Story 1, scenarios 2-3; Story 3, scenario 5.
- **FR-013**: Unsupported SQLCMD constructs and repeat-count separators MUST be rejected before any batch in the affected script executes, with a diagnostic identifying the unsupported construct. Acceptance: unsupported-construct edge case.
- **FR-014**: Dependency initialization MUST use one new private parameterized function accepting a required DLL filename, including `Microsoft.Data.SqlClient.dll`, `Microsoft.SqlServer.TransactSql.ScriptDom.dll`, and other bundled managed libraries without a hardcoded name list. It MUST resolve the current runtime's selected-distribution bundle, reuse an already-loaded assembly, support caller-specified required-type validation, and terminate missing/corrupt/incompatible loads with dependency/runtime/path and rebuild context. Existing library-specific loading implementations MUST be replaced by calls to this function; assembly initialization MUST remain in designated bootstrap entry points and MUST NOT add public exports. Acceptance: Story 4, scenarios 1-5; dependency-resolution edge case.
- **FR-015**: For each script with executable batches, `Invoke-Migration` MUST create, open, use, and dispose a separate connection configured by the supplied connection string under FR-016. It MUST use that session for every batch in that file and isolate it from history and subsequent files. It MUST NOT open a script connection for invalid or zero-batch scripts, use history resources, or fall back to the history connection if initialization fails. Acceptance: Story 5, scenarios 1-6.
- **FR-016**: `Invoke-Migration` MUST accept mandatory string `-ConnStr` and the existing `-Script` parameter instead of `-SqlCmd`. After complete script validation, it MUST initialize and open its target connection from that supplied string, create and own its execution command, retain the existing unbounded script timeout, and release command, connection, and suppression scope on all exits. The public caller MUST pass its original `ConnStr`; cloning/rebinding/restoring a caller command is no longer part of the executor contract. `Set-Executed -SqlCmd` MUST remain unchanged. Acceptance: Story 6, scenarios 1-4; Story 5, scenarios 3-4.

### Key Entities

- **Migration script**: A configured phase-relative file with source contents, a SHA-256 checksum, and an ordered collection of executable batches.
- **Migration batch**: A unit of script execution with a source position and execution order; all batches of a script share the supplied database session.
- **Caller-owned history command**: The command supplied only to `Set-Executed`, retaining its connection, timeout, assigned transaction, and caller-owned lifetime.
- **Script target connection string**: The original caller-supplied configuration identifying the target server/database and connection-string authentication/options, passed directly to the executor and excluded from diagnostics.
- **Script execution connection and command**: Resources created and owned by `Invoke-Migration` for one file, with session state shared only across that file's batches.
- **Execution history entry**: The existing record associating a script identity and phase with its successful checksum and database UTC execution timestamp. Completion applies to the whole script.

### Acceptance Coverage and Dependencies

The user explicitly selected the command type and parser. These are binding design constraints rather than optional implementation suggestions. Planning must cover dependency packaging and initialization without restoring a dependency on the SqlServer PowerShell module. The existing uncommitted ScriptDom package reference in `build/SqlClientLoader.csproj` is context, not evidence that dependency delivery is complete.

Regression coverage must include clean imports without the removed module, source and packaged loading, the supported platform packaging paths, batch boundaries, session continuity within a script, command ownership and settings, command reuse, successful and forced history writes, parse and runtime failures, history-write failure, cleanup, preview, and retry. Database-specific execution and history behavior require an explicitly selected SQL Server test database where mocks cannot establish correctness. No performance improvement is claimed; the outcome is reduced prerequisites with reliable migration behavior.

The additional loader requirement supersedes the earlier design using separate SqlClient and ScriptDom loading functions. Validate the shared function with both dependencies, an additional bundled managed library, repeated initialization, required-type checks, dependency faults, and source/package provenance. Existing execution evidence predates FR-014 and does not establish that this addition is implemented.

FR-015 supersedes shared script/history sessions. FR-016 additionally replaces the executor's borrowed-command input with a connection string and internally owned command. Verify original-string forwarding, target/authentication options, independent resources, final transaction validation, open/command-creation/execution/cleanup failures, and zero opens for rejected/empty files. Clone/rebinding/restoration and externally assigned executor transaction requirements are superseded; history transaction support remains. Earlier results establish only their historical interfaces, not FR-016 acceptance.

Applicable constitution requirements are Principles I-III for durable completion records, deterministic ordering, checksum validation, preview safety, parameterized values, terminating failures, and idempotent retries; Principle IV for dependency delivery, documented contracts, and runtime/platform compatibility; and Principle V for regression evidence, actionable errors, and SQL Server validation. Implementation must analyze modified PowerShell files using the project PSScriptAnalyzer configuration and record unavailable checks honestly.

The original specification identified a constitution conflict in the supported stack. The approved constitution 1.1.0 amendment now replaces the SqlServer PowerShell prerequisite with bundled SqlClient and ScriptDom; the approved module release is 0.1.0. Adoption is recorded in `validation.md`. The new connection-ownership requirement retains the active principles for bounded target operations, reliable cleanup, deterministic completion, and explicit validation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can import the delivered module and complete the representative migration workflow with zero installations of the removed PowerShell prerequisite and zero changes to existing public invocation parameters.
- **SC-002**: Across all supported batch-boundary acceptance cases, 100% of executable batches run exactly once in the expected order, with zero unintended splits or lost session state within a script.
- **SC-003**: Across all syntax, runtime, and history-failure acceptance cases, zero failed attempts create or update a successful completion record and zero later scripts run after the failure.
- **SC-004**: All preview and declined-confirmation acceptance cases produce zero script effects and zero history writes while retaining the expected validation and reporting behavior.
- **SC-005**: Across all ownership and reuse acceptance cases, history retains 100% of caller-selected command settings, the executor touches zero history resources, and both owners attempt cleanup of every resource they created on success and failure.
- **SC-006**: An operator following the updated setup and migration instructions can complete import, a multi-batch migration, and a documented failure/retry exercise without installing the removed prerequisite or needing an undocumented workaround.
- **SC-007**: Maintainers can initialize both existing required libraries and one additional bundled library through one loading implementation, with zero new library-specific loader functions; 100% of the defined reuse, compatibility, failure, and distribution-provenance cases retain their required outcomes.
- **SC-008**: Across all script-session isolation cases, 100% of files execute independently of the history session, all batches within each file share their script session, and zero script-induced connection/session changes reach history or the next file. Invalid and zero-batch scripts open zero execution connections.
- **SC-009**: Every direct-executor acceptance case can be invoked using only a connection string and script path, with zero caller-created database resources; all caller-forwarding cases retain the original target/options and all failure cases leave zero owned resources without a cleanup attempt.

## Assumptions

- This addition updates requirements and design only. Earlier implementation results remain evidence for their original interfaces; the replacement ConnStr executor implementation and validation are pending T056-T058.
- The latest request overrides the original command-input requirement only for `Invoke-Migration`: it now takes `ConnStr`. `Set-Executed` continues to take `SqlCmd`; public migration parameters and `Get-Executed` remain unchanged.
- Target database, authentication, and connection options for script execution come from the original supplied connection string, not a history connection's current state or credential/token properties. The executor takes no caller command/transaction. History still supports caller-assigned transactions; script ambient suppression and explicit transaction completion rules remain.
- Session continuity is required across batches within each script. Every executable file uses a separate execution connection; session state is isolated from history and subsequent files. Connection pooling does not change this observable isolation requirement. Scripts must remain independently retryable and idempotent.
- The supported authoring contract is ordinary T-SQL accepted by the requested parser with standalone `GO` batch separators. SQLCMD preprocessing, variable substitution, repeat-count separators, and support for additional parser dialects are outside scope.
- Existing SQL and history writes remain separate completion steps. There is no new automatic rollback guarantee: earlier committed batches may survive a runtime failure, and a script may succeed before its history write fails.
- Existing migration schema, configuration, public exports, and supported PowerShell/platform baseline remain unchanged. The new parser dependency has the specific purpose of recognizing and validating script batches.
