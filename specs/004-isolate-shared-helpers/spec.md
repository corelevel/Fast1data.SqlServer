# Feature Specification: Predictable Internal Imports and Isolated Shared Helpers

**Feature Branch**: `dev` (existing branch; no branch hook configured)

**Created**: 2026-10-31

**Status**: Draft

**Input**: User description: "Make shared-helper resolution deterministic across audit, archiving, and migration. Importing an internal module must not replace another component's helpers or change its logging behavior. Preserve the three public commands, existing SQL behavior, class availability, and cleanup/error handling. Logging must retain Warning and Verbose levels and honor the caller's verbosity settings. Verify behavior across relevant import orders, repeated imports, and both source and packaged modules. Retain the audit verbose regression test and cover archiving logging and SQL-helper behavior."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep requested operational messages visible (Priority: P1)

As an operator running audit, archiving, or migration, I need my requested progress messages and warnings to remain reliable when other components have been loaded, so I can understand what an operation did without restarting my session or changing load order.

**Why this priority**: The reported audit regression suppresses requested verbose output after an archiving import, concealing useful operational information while the public command list still looks correct.

**Independent Test**: Run controlled audit, archiving, and migration scenarios that produce known progress and warning messages before and after loading other internal components. Capture message levels and counts with verbosity enabled and disabled.

**Acceptance Scenarios**:

1. **Given** audit discovery returns no files and the archiving model is imported into the main module after its shared helpers are available, **When** `Invoke-Fast1Audit -ConnStr 'unused' -Folder 'unused' -Verbose 4>&1` runs in the existing isolated test fixture, **Then** exactly one captured verbose message contains `No audit files found`, preserving the existing regression test in `Fast1data.SqlServer/tests/Audit.Common.Tests.ps1`.
2. **Given** each component has a scenario that emits progress, **When** the operator enables verbose output for that invocation before or after other components are loaded, **Then** the same expected progress messages appear on the verbose stream without omissions or import-induced duplicates.
3. **Given** the same progress scenarios, **When** verbose output is disabled, **Then** no verbose messages appear; an explicit invocation setting takes precedence over the ambient verbosity setting, and an invocation without an override follows the applicable ambient setting.
4. **Given** an operation produces a warning, **When** verbose output is disabled and warnings are enabled, **Then** the warning still appears on the warning stream, with its existing severity and message meaning, in every covered loading sequence.
5. **Given** a verbose invocation is followed by a quiet invocation or the reverse, **When** both run in the same session, **Then** each honors its own settings and leaves the caller's ambient preferences unchanged.

---

### User Story 2 - Load components without changing their dependencies (Priority: P1)

As a maintainer or automation author combining audit, archiving, and migration in one session, I need each component to keep using its intended helpers so that importing another component cannot silently change existing behavior.

**Why this priority**: Logging is the confirmed symptom, but the same shared loading arrangement includes query and cleanup behavior on which successful and failed operations depend.

**Independent Test**: Compare helper ownership and representative query, error, and cleanup outcomes against an isolated component baseline across the loading matrix below, including execution through archiving's existing classes.

**Acceptance Scenarios**:

1. **Given** a component's helper dependencies are resolved, **When** another internal module is imported afterward, **Then** the importing component retains its intended helper ownership and behavior, and the imported module can still use its own required dependencies.
2. **Given** internal components are loaded before the main module, after it, or repeatedly, **When** audit, archiving, and migration are invoked, **Then** their dependencies remain available and their results match the same isolated-operation expectations.
3. **Given** representative parameterized query and non-query operations used by audit, archiving, and migration, **When** those operations run after imports, **Then** query text and parameter values, returned data shapes, affected-row results where applicable, and error propagation retain their existing contracts.
4. **Given** an archiving operation encounters a query, initialization, or processing failure, **When** cleanup runs after imports, **Then** acquired resources are released according to the existing contract, required constraint restoration is attempted, and the original error remains identifiable even if cleanup also fails.
5. **Given** existing archiving callers load and use the archiving classes, **When** shared helpers are isolated, **Then** class loading, construction, and execution still succeed on supported paths, including access to logging, query, and cleanup dependencies.
6. **Given** representative audit and migration operations succeed or fail after imports, **When** they exit, **Then** their existing cleanup and error contracts remain unchanged; migration execution errors still terminate processing.

---

### User Story 3 - Use the same contract from source and packages (Priority: P2)

As a module consumer, I need the installed package and source checkout to expose the same commands and operational behavior so that packaging does not reintroduce a loading-order defect.

**Why this priority**: Source-only checks and public-export checks can both pass while internal command resolution differs in a packaged module.

**Independent Test**: Execute the same import, logging, class-availability, query, and cleanup acceptance scenarios against a source module and a newly built package in separate clean sessions.

**Acceptance Scenarios**:

1. **Given** either distribution is imported, **When** consumers enumerate the main module's public commands, **Then** exactly `Invoke-Fast1Audit`, `Invoke-Fast1Archiving`, and `Invoke-Fast1Migration` are available with their existing parameters, and internal helpers do not become public commands.
2. **Given** identical fixture inputs and loading sequences, **When** the acceptance scenarios run against source and packaged distributions, **Then** both satisfy the same expected outputs, message levels and counts, error behavior, cleanup, and class-availability requirements.
3. **Given** existing audit, archiving, and migration configuration and persisted progress, **When** operations run with the changed module, **Then** configuration formats, progress interpretation, processing order, and recovery behavior remain compatible without a data or configuration migration.

### Edge Cases

- Importing the archiving model after the main module already resolved its local logger must not replace that logger, even if the two definitions share identical source text.
- Repeating an internal import, including forced re-import where already supported, must not change helper ownership, duplicate operational messages, or break class consumers.
- The main module's three-command export list may remain correct while an internal helper is replaced; acceptance must check both boundaries independently.
- Explicit verbose suppression in a verbose ambient session and explicit verbose enablement in a quiet session must behave consistently through internal calls.
- An empty audit folder, an empty archiving group, and a migration with nothing to run must retain their expected progress behavior without requiring successful data mutations.
- A primary operation failure followed by cleanup failure must retain the original error and actionable cleanup context without exposing credentials.
- Source and packaged checks must start independently so previously loaded modules or classes cannot mask missing dependencies.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Internal imports MUST preserve the intended ownership and resolution of helpers already used by audit, archiving, and migration. Loading another component MUST NOT replace a component's helpers merely because their names match. Acceptance: Story 2, scenarios 1–2.
- **FR-002**: The feature MUST identify the owner or intended local owners, consumers, and required cross-module dependencies of each helper shared by the affected components, including logging, SQL query, and cleanup helpers. Every identified dependency MUST remain available after imports, with no unintended helper exposure to other components or consumers. Acceptance: review the dependency inventory and verify Story 2, scenarios 1–6, and Story 3, scenario 1.
- **FR-003**: Logging MUST retain Warning and Verbose levels, their respective streams, existing message meaning and formatting, and the caller's verbosity controls. Imports MUST NOT suppress requested messages, duplicate them, or mutate caller preferences. Acceptance: Story 1, scenarios 1–5.
- **FR-004**: The existing audit verbose regression test MUST remain an acceptance test with its one-message expectation intact; resolving the defect MUST NOT depend on weakening that expectation or arranging a favorable load order. Acceptance: Story 1, scenario 1, across both distributions.
- **FR-005**: Archiving MUST retain its own progress and warning behavior and access to SQL query and cleanup helpers after helper boundaries change. Acceptance: Story 1, scenarios 2–5, and Story 2, scenarios 3–5, exercised through archiving operations.
- **FR-006**: The public interface MUST remain exactly the three existing public commands with unchanged parameters and supported runtime/platform contracts. Internal helpers MUST remain private to their intended consumers. Acceptance: Story 3, scenarios 1–2, on supported import paths.
- **FR-007**: Existing archiving class availability and behavior MUST remain compatible with current callers, including callers using `using module`. Acceptance: Story 2, scenario 5, in both distributions.
- **FR-008**: Existing SQL behavior, parameter handling, result contracts, configuration, schemas, processing order, persisted progress, and retry semantics MUST remain unchanged. Acceptance: Story 2, scenario 3, and Story 3, scenario 3, using existing success, failure, and retry fixtures.
- **FR-009**: Existing resource cleanup, constraint restoration, and error handling MUST remain intact across imports, including initialization failure, processing failure, cleanup failure, and successful completion. Acceptance: Story 2, scenarios 4 and 6, with the existing cleanup and recovery expectations.
- **FR-010**: Acceptance coverage MUST include the loading matrix below for both source and packaged modules, with independent checks of internal helper ownership, public exports, messages, class availability, and representative query and cleanup outcomes. Acceptance: all three stories.

### Acceptance Coverage and Dependencies

The minimum loading matrix covers a clean main-module import; the archiving model loaded before the main module; the archiving model imported into the main module after shared helpers; and repeated internal imports, including forced imports on existing supported paths. Run the three public operations in all six relative orders against controlled fixtures, without introducing unsupported class hot-reloading requirements. Apply these cases to both source and packaged distributions and include any additional internal modules identified as sharing the affected helpers.

For logging, cover explicit verbosity on and off plus inherited ambient on and off, including conflicting explicit and ambient settings. Exercise a warning-producing path with verbose output disabled. For dependency behavior, include query success and failure, normal cleanup, partial initialization failure, and cleanup failure. Reuse existing success, interruption, and retry fixtures to establish compatibility rather than asserting new failures in helpers that have not been shown to fail.

Applicable constitution constraints are Principle I (data integrity and resumability), Principle II (deterministic migrations and preview behavior), Principle III (bounded database operations, error propagation, and secret protection), Principle IV (public and portable runtime contracts), and Principle V (regression evidence and operational visibility). Implementation validation must cover affected imports and packaging, use SQL Server checks where substitutes cannot establish correctness, record unavailable checks, and satisfy the constitution's analysis requirements for modified PowerShell files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The empty-audit regression produces exactly one expected verbose message in 100% of applicable loading cases in both distributions.
- **SC-002**: Across all three operations and the defined acceptance matrix, 100% of expected progress and warning messages retain their levels and meanings, with zero import-induced omissions or duplicates and zero verbose messages when verbosity is disabled.
- **SC-003**: Consumers retain exactly three public operations, with zero added public helpers and zero required changes to existing invocation parameters or configuration.
- **SC-004**: All defined success, failure, cleanup, and retry scenarios satisfy their existing operational expectations in both distributions, with zero differences attributable to loading order.
- **SC-005**: Operators can run all six orderings of audit, archiving, and migration in one session without restarting the session or applying a load-order workaround, and obtain the same expected outcomes as isolated runs.

## Assumptions

- The supplied diagnosis establishes the audit logging regression. Other shared helpers require compatibility verification; this specification does not claim that all of them currently fail.
- A shared helper may legitimately have multiple local owners. The requirement is predictable ownership and explicit dependency boundaries, not necessarily a single shared runtime instance.
- The implementation approach remains open. Export restrictions are a candidate for planning; wholesale replacement of imports, a new logging framework, and unrelated restructuring are not requirements.
- Existing supported runtime/platform contracts, dependency versions, public help, and operational behavior remain the compatibility baseline. No new public commands, database schema changes, or business-workflow changes are in scope.
- Existing test fixtures and packaging infrastructure are available for reuse. Database-dependent verification requires an explicitly selected test database and documented prerequisites; unavailable execution checks must be reported rather than treated as passing.
- Loading-order comparisons use equivalent controlled inputs and compare operational content and severity; naturally varying timestamps are not considered behavioral differences.
