---
description: "Implementation tasks for predictable internal imports and isolated shared helpers"
---

# Tasks: Predictable Internal Imports and Isolated Shared Helpers

**Input**: Design documents from `specs/004-isolate-shared-helpers/`: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/shared-helper-boundaries.md`, and `quickstart.md`.

**Prerequisites**: Read the input documents, `AGENTS.md`, and `.specify/memory/constitution.md`. Work on the existing branch; no branch creation is required.

**Tests**: Explicitly required by the specification. Add regression assertions before the associated production changes and demonstrate the existing logging failure. Compatibility assertions may already pass; do not invent failures or weaken existing expectations.

**Organization**: Tasks are grouped by user story. US1 includes the export restriction because it is needed to fix the audit regression; US2 then verifies the wider dependency boundary. US3 applies the completed behavior to both distributions.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies tasks that can run alongside other tasks in the same ready group on different files. It does not waive phase or explicit prerequisites.
- `[US1]`, `[US2]`, and `[US3]` map to the specification's user stories.
- All paths below are relative to the repository root. Fixture files live beneath `Fast1data.SqlServer/tests/fixtures/` without `.Tests.ps1` names to prevent recursive matrix discovery.
- Expected production changes are limited to `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` and `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1`. Change the loader, logger, SQL bodies, manifest, or packaging only if acceptance evidence demonstrates a necessary defect; record that evidence.
- Every modified PowerShell file must retain multiline control-flow blocks, same-line opening braces, standalone closing braces, and tab indentation. Run affected tests and PSScriptAnalyzer before considering its implementation complete; T031 consolidates the final evidence.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the unchanged contract and executable validation prerequisites without modifying production behavior.

- [X] T001 [P] Create `specs/004-isolate-shared-helpers/validation.md` with revision, PowerShell/Pester/PSScriptAnalyzer/SqlServer versions, declared runtime-asset availability, and a fresh-process baseline of `Fast1data.SqlServer/tests/Audit.Common.Tests.ps1`; record actual counts and the exact-one verbose failure separately from planning evidence, without exposing credentials.
- [X] T002 [P] Capture the unchanged public contract into `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json` from `Fast1data.SqlServer/Fast1data.SqlServer.psd1` and the three public functions in a clean process; normalize command/parameter types, attributes, defaults, aliases, validation, parameter sets, common parameters, and SupportsShouldProcess so later tests compare against a fixed baseline rather than regenerating expected values from changed code.
- [X] T003 [P] Confirm and document executable prerequisites in `specs/004-isolate-shared-helpers/quickstart.md`: controlled-suite selection excludes integration filenames before discovery; live suites need explicitly selected disposable SQL resources and local fixture settings; packaging runs live suites; record Windows/Linux/macOS availability and audit's Windows/Linux restriction without introducing dependencies or a new configuration interface.

**Checkpoint**: Baseline expectations, tools/assets, and unavailable external prerequisites are explicit. Missing SQL/alternate hosts do not prevent controlled implementation but leave their validation gates outstanding.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build one reusable harness for all three stories.

- [X] T004 Create `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` with selected distribution-root, L1–L5 loading-scenario, and operation-permutation inputs; bootstrap SqlClient from that root before model-first loading, implement clean/root-then-model/repeated/supported-forced imports including Metadata and GenericSqlParam, retain one session per tuple, and return structured observations plus a nonzero failure exit. Follow the acceptance-record rule: "Each distribution/loading/permutation tuple gets a fresh process; operations and sequential verbosity changes within a tuple share that process to expose contamination." Do not import another distribution or recursively discover the matrix.
- [X] T005 Create `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1` to launch the worker from T004 in a fresh `pwsh -NoProfile` process for each of five loading scenarios × six orders (A-R-M, A-M-R, R-A-M, R-M-A, M-A-R, M-R-A); derive the selected distribution from the test location, propagate worker failures and missing results, and require exactly 30 unique tuples per distribution with no missing cases, zero-discovery success, or unexpected skips.

**Checkpoint**: Harness can load every tuple from one explicitly selected root and surface failures. Story assertions are added below; harness-only success is not acceptance.

## Phase 3: User Story 1 — Keep requested operational messages visible (Priority: P1) — MVP

**Goal**: Preserve real verbose/warning output and invocation-local preferences after imports.

**Independent Test**: In fresh source workers, all 30 tuples run real audit, archiving, and migration loggers through six ambient/explicit verbosity combinations, both sequential on/off orders, and success/failure paths. Audit's retained adverse-import fixture captures exactly one `No audit files found` message; enabled archiving emits group-found/no-tables progress and migration retains `Nothing to run` plus existing evaluation messages. Quiet calls emit no verbose records, warnings remain stream 3, and caller preferences are unchanged.

### Tests for User Story 1

- [X] T006 [P] [US1] Retain and run the adverse-import regression in `Fast1data.SqlServer/tests/Audit.Common.Tests.ps1` unchanged in meaning: exactly one total captured verbose message containing `No audit files found`, no mocked logger, and no favorable import ordering; use its failing baseline to guard T009.
- [X] T007 [P] [US1] Add real-logger archiving execution cases in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, using controlled connection/discovery boundaries and actual class methods; replace the literal `.Execute()` source-text assertion with behavior proving one construction/execution request, cover nested logging and warning-producing paths, and verify single-use enforcement and parameterless execution remain compatible.
- [X] T008 [P] [US1] Add logging assertions to `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` for real public audit/archiving/migration calls in the selected order: ambient Continue/SilentlyContinue × explicit true/false/absent, verbose→quiet and quiet→verbose, session and function-local ambient callers, and unchanged preferences after success/failure. Apply the data-model rules verbatim: effective preference is `System.Management.Automation.ActionPreference` for "one invocation"; "Read the effective value visible to the root adapter after public common-parameter binding"; logger levels are "Existing `Verbose` or `Warning`"; "Retain default `Verbose`; warning is independent of verbose suppression"; and "Retain timestamp, level marker, message meaning, and stream". Assert `[yyyy-MM-dd HH:mm:ss.fff] [Level] Message`, stream 4 versus stream 3, no unintended success output, and exact normalized message counts without mocking the logger.

### Implementation for User Story 1

- [X] T009 [US1] Explicitly suppress function and alias exports in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` while retaining its local dot-sourced SQL/cleanup/logger/comparison/delay dependencies and existing `using module` declarations; implement the helper policy "Private internal helper; no accidental export into another owner" without changing root loading order or the public manifest.
- [X] T010 [US1] Add `TableGroup.Execute([System.Management.Automation.ActionPreference]$VerbosePreference)` in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, following "Same enum; overload method-local parameter" and "Name `$VerbosePreference` so nested calls use the scoped preference"; delegate exactly once to existing `Execute()`, preserving all constructors, identity/source/destination/DisableFK/SourceTables fields and the single-use Started owner. Preserve the rule: "The new overload must not set `Started` or duplicate initialization/cleanup; the existing method remains the single owner." Do not assign module/global preferences or add per-table/persisted logging state.
- [X] T011 [US1] Forward the adapter's effective `$VerbosePreference` to the new execution overload in `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1` and update its internal help to explain invocation scope; preserve public signatures and no-output behavior, including "Explicit `-Verbose:$false` overrides verbose ambient state; absent override follows applicable ambient state."
- [X] T012 [US1] Run the retained audit suite, archiving execution coverage, and all 30 source logging tuples from `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1` in fresh processes; record counts, expected record comparisons, preference restoration, and any failure details in `specs/004-isolate-shared-helpers/validation.md` after T006–T011, resolving regressions before the MVP checkpoint.

**Checkpoint**: US1 is independently demonstrable from source. It is an MVP validation milestone, not full package/release acceptance.

## Phase 4: User Story 2 — Load components without changing their dependencies (Priority: P1)

**Goal**: Establish that each component retains its intended helpers, class APIs, SQL behavior, and cleanup/error semantics.

**Independent Test**: Against the source root, compare defining module/session-state identity and resolved paths with isolated ownership expectations across all 30 tuples. Execute actual SQL helpers in root and model scopes with controlled providers, literal class imports, and existing recovery suites; assert unchanged outputs, original errors, all required disposal attempts, and constraint-restoration behavior.

### Tests for User Story 2

- [X] T013 [P] [US2] Add ownership assertions to `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` for every dependency in `specs/004-isolate-shared-helpers/research.md`: log/query/cleanup/comparison/delay helpers in both legitimate owners, root-only runtime/checksum/path/adapter functions, and model-only factories/actions. Use "Defining module/session-state identity and script source path" rather than text/name equality; capture root identity before adverse imports, compare L2 with isolated root expectations, allow refreshed model identity only on supported re-import paths, and verify model/Metadata/GenericSqlParam export no helper commands while all resolved module paths remain under the selected root.
- [X] T014 [P] [US2] Extend `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` with reusable root-local and model-local real query-helper cases asserting query text/type and `GenericSqlParam` fields `Value: object`, `Type: SqlDbType`, `Size: int`, `Precision: byte`, `Scale: byte`; preserve "reject other object types or missing type as currently implemented, prefix names as before, map null values to `DBNull`, and apply positive size/precision/scale settings." Verify "Scalar mode returns the provider's scalar result; non-query mode emits no success output." Inject command-construction, parameter-validation, and execution errors and retain audit row shapes and separate archiving row-counter contracts without rewriting production SQL.
- [X] T015 [US2] Extend cleanup cases in `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` after T014 to assert "A query owns its command and borrows its connection" and "Readers precede commands, and owned connections follow commands; borrowed connections remain their owner's responsibility." Cover successful, cleanup-only, and primary-plus-cleanup exits; preserve exception-chain retrieval/deduplication and keys `Fast1Sql.CleanupFailures` / `Fast1Archiving.CleanupFailures`, with existing `Action`, `ResourceRole`, `GroupName`, `SourceTable`, `ProcessStateId` context and error-type/fixed-message fields. Enforce "If a primary error exists, cleanup annotates it without replacing it" and "Without a primary error, the first cleanup failure becomes terminating after remaining attempts"; "Do not add credentials, connection strings, or raw SQL to context."
- [X] T016 [P] [US2] Create `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Classes.ps1` with literal relative `using module` declarations for the selected distribution's model, metadata, and SQL-parameter modules; after assembly bootstrap, verify loading/construction of TableGroup, Table, ProcessState, GenericSqlParam, TableColumn, IndexColumn, and Index, preserving existing metadata and ProcessState fields and validation. Exercise parameterless and preference-overload execution on fresh groups with actual model-local dependencies and single-use rejection, without requiring changed-class hot reload.
- [X] T017 [P] [US2] Extend/reuse `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` under adverse imports for success, partial initialization, processing failure, partial constraint disable/restoration, cleanup-only and combined failures, interruption/lost-response retry using a fresh group, configured archive/purge ordering, and checkpoint completion; retain existing ProcessState IDs/dates/key bounds/row totals/per-batch/configuration-connection semantics and execute representative class paths through real query/cleanup helpers rather than mocking those helpers throughout.
- [X] T018 [P] [US2] Extend/reuse `Fast1data.SqlServer/tests/Migration.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` under adverse imports for ordered execution, SHA-256 history checks, changed-script rejection, explicit force/ignore behavior and conflicts, duplicate/path/case/separator validation, no-op and `-WhatIf` behavior, history-recording failure/retry, and terminating execution errors that prevent later scripts/history writes.

### Integration for User Story 2

- [X] T019 [US2] Wire T014–T018 into `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` and `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1` after T013–T018: execute representative root/model SQL and audit/migration cleanup/error cases within each tuple after its imports/operation sequence, run the literal class probe after bootstrap in fresh processes, and invoke explicit controlled Pester containers for supplemental suites without rediscovering the matrix or resetting the adverse imports before assertions.
- [X] T020 [US2] Run the complete source controlled suite set from `specs/004-isolate-shared-helpers/quickstart.md` after T019, including applicable `Fast1data.SqlServer/tests/Audit.Windows.Tests.ps1` or `Fast1data.SqlServer/tests/Audit.Linux.Tests.ps1`, and record owner identities, 30 unique tuple results, class availability, SQL/error/cleanup and recovery outcomes in `specs/004-isolate-shared-helpers/validation.md`; treat missing required cases or unexpected skips as incomplete acceptance.

**Checkpoint**: US2's controlled source contract is independently verifiable. Durable SQL/foreign-key effects still require the live validation tasks in US3.

## Phase 5: User Story 3 — Use the same contract from source and packages (Priority: P2)

**Goal**: Verify unchanged public/configuration contracts and equivalent source/package outcomes, including SQL-specific and platform obligations.

**Independent Test**: Run the same assertions against source and an actual newly staged package in separate clean processes. Require 30 tuples each (60 total), full public-parameter baseline equivalence, class/SQL/cleanup/logging parity, retained runtime assets, and required live SQL and supported-host evidence. A staged directory left after packaging failure is not a passing package.

### Tests for User Story 3

- [X] T021 [P] [US3] Add public-contract and distribution checks to `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1` using `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json`: exactly Invoke-Fast1Audit, Invoke-Fast1Archiving, Invoke-Fast1Migration; unchanged full parameter metadata/defaults/attributes/common parameters/SupportsShouldProcess; no new function/alias/variable/cmdlet exports; all loaded module/fixture paths within the selected root; and declared win-x64/linux-x64/osx-x64 assets preserved. Compare normalized source/package observations without sharing a PowerShell session or requiring the other distribution during ordinary single-root test discovery.
- [X] T022 [P] [US3] Adapt existing fixtures in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` to exercise real success, initialization/processing failure, interruption/retry, durable progress, configured processing order, and foreign-key restoration after adverse imports; resolve module paths from the selected distribution, retain unique disposable configuration/source/destination databases and teardown attempts, and keep local credentials out of committed settings and logs.
- [X] T023 [P] [US3] Adapt existing fixtures in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` to run after adverse imports against an explicitly selected disposable database, preserving execution/history order, checksum/force/ignore/preview behavior, termination, and history-failure recovery with distribution-relative imports and reliable teardown.
- [X] T024 [P] [US3] Adapt existing fixtures in `Fast1data.SqlServer/tests/Audit.Integration.Windows.Tests.ps1` to run after adverse imports from the selected distribution, retaining result shapes, durable offsets including intentionally ignored records, success/failure cleanup, interruption/resume behavior, and closed immutable audit-file prerequisites on an explicitly selected test database.
- [X] T025 [P] [US3] Adapt existing fixtures in `Fast1data.SqlServer/tests/Audit.Integration.Linux.Tests.ps1` to run after adverse imports from the selected distribution with the same audit progress/error/retry expectations, preserving smbclient/UNC/shared-file prerequisites and unique test database teardown without exposing credentials or adding macOS audit-discovery support.

### Integration and Validation for User Story 3

- [X] T026 [US3] After T021–T025, run the source controlled matrix and required live suites using the reviewed disposable SQL fixtures in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`, and the applicable audit integration file; record actual durable effects, recovery/constraint outcomes, fixture prerequisites, and any unavailable checks in `specs/004-isolate-shared-helpers/validation.md`. Unavailable SQL evidence remains an open gate, not a passing task.
- [X] T027 [US3] Validate the actual local packaging path with `out/publish.ps1` after source gates pass and its live-test settings are ready; use `build/build.ps1` only if required runtime assets need rebuilding, preserve all three runtime directories and existing versions, and record manifest/analyzer/test results in `specs/004-isolate-shared-helpers/validation.md`. Do not introduce validation bypasses, publish to a gallery, or describe partially staged output as a successful package.
- [X] T028 [US3] Run `out/Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`, the retained packaged audit regression, all packaged controlled recovery suites, class fixtures, and required packaged live SQL suites in fresh processes after T027; compare normalized observations with source in `specs/004-isolate-shared-helpers/validation.md`, require exactly 60 combined unique loading/order tuples, and verify source fallback cannot satisfy package dependencies.
- [ ] T029 [US3] Execute and record the supported-host checks described in `specs/004-isolate-shared-helpers/quickstart.md` for x64 Windows, Linux, and macOS against both distributions, including import/classes/shared helpers/migration/archiving and existing unsupported audit-discovery behavior on macOS; record host-specific counts and unavailable checks in `specs/004-isolate-shared-helpers/validation.md` without claiming unexecuted platforms pass.

**Checkpoint**: Both distributions satisfy the same contract. SQL, package, or host prerequisites that remain unavailable must be visible as outstanding acceptance work; material unverified data-integrity risks block release.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Make the final validation and operational guidance reviewable.

- [X] T030 [P] Update `specs/004-isolate-shared-helpers/quickstart.md` to match the implemented worker inputs, matrix/class commands, controlled-suite selection, actual package workflow, and live-test prerequisites; reconcile `specs/004-isolate-shared-helpers/research.md` with verified helper ownership and preserve existing configuration, no-migration, single-directory/single-group, and recovery guidance.
- [X] T031 [P] Run Invoke-ScriptAnalyzer on every changed/new `.ps1`, `.psm1`, and `.psd1` file with repository settings if available and SQL-client types loaded, check `AGENTS.md` formatting, resolve introduced warnings/errors, and record results or analyzer unavailability plus unrelated existing findings in `specs/004-isolate-shared-helpers/validation.md`; do not suppress rules or extend packaging filters merely to pass.
- [X] T032 Review final evidence against FR-001–FR-010 and SC-001–SC-005 in `specs/004-isolate-shared-helpers/spec.md`, record the traceability and any unresolved acceptance gates in `specs/004-isolate-shared-helpers/validation.md`, and reconcile completion checkboxes in `specs/004-isolate-shared-helpers/tasks.md` with actual results. Confirm no unintended configuration/schema/runtime/dependency/public-contract changes; rerun affected checks only if review or analysis required further changes, and leave unavailable mandatory validation tasks unchecked.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup: T001 || T002 || T003
  → Foundation: T004 → T005
  → US1: (T006 || T007 || T008) → T009 → T010 → T011 → T012
  → US2: (T013 || [T014 → T015] || T016 || T017 || T018) → T019 → T020
  → US3: (T021 || T022 || T023 || T024 || T025) → T026 → T027 → T028 → T029
  → Polish: (T030 || T031) → T032
```

`||` denotes tasks on distinct files once prerequisites are complete. Execution of this task-generation workflow does not itself launch parallel implementation agents.

### User Story Dependencies

- US1 depends only on setup/foundation and supplies the minimal production repair.
- US2 depends on US1's export boundary and overload so acceptance can verify the completed implementation. Its SQL/class/cleanup test authoring can be prepared independently, but shared worker and archiving-test edits must be serialized with US1.
- US3 depends on US1 and US2 for complete source/package parity; its distinct integration files can be prepared independently once the harness contract is stable. Final acceptance runs follow the graph.
- T026 requires selected live SQL fixtures; T027 runs live suites as part of packaging and depends on source acceptance. T028 requires a successfully validated package. T029 requires each supported host. Missing environments do not authorize marking these gates complete.
- T030 and T031 write separate files; T032 waits for both. Review can document unavailable checks even when full release acceptance remains incomplete.

### Within Each User Story

- Write regression/contract assertions before the production change they validate; preserve already passing compatibility coverage.
- Run real loggers and class methods with controlled external boundaries. Separate owner/path assertions from public-export checks.
- The SQL/result/cleanup contracts remain existing behavior; neither new persistence entities nor API endpoints are needed.
- Reuse recovery fixtures rather than inventing new runtime abstractions. Do not allow integration setup to run during controlled-only discovery.

## Parallel Example: User Story 1

After T005, run these independent tasks together:

```text
T006: Preserve/run the audit regression in Fast1data.SqlServer/tests/Audit.Common.Tests.ps1.
T007: Add archiving behavior tests in Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1.
T008: Add logging scenarios in Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1.
```

Then perform the model export/overload and adapter changes sequentially, followed by source validation.

## Parallel Example: User Story 2

After T012, T013 (worker ownership), T014 (SQL tests), T016 (class fixture), T017 (archiving recovery), and T018 (migration recovery) use distinct files and can proceed together. T015 follows T014 in the same SQL test file. T019 waits for the entire group before connecting the assertions to every worker.

## Parallel Example: User Story 3

After T020, T021 (matrix contract), T022 (archiving integration), T023 (migration integration), T024 (Windows audit integration), and T025 (Linux audit integration) can be authored together. Source live validation, packaging, and package comparison remain sequential. Separate host runs may execute concurrently on independent disposable environments while collecting T029 evidence.

## Implementation Strategy

### MVP First (User Story 1)

1. Complete setup and foundation, retaining the unchanged contract and failing audit baseline.
2. Complete US1's logging tests and two-file production repair.
3. Demonstrate exactly one audit record, real archiving/migration progress, warning independence, and no preference leakage in all source tuples.
4. Treat T012 as the MVP checkpoint; continue through dependency, SQL, package, and platform gates before claiming full acceptance.

### Incremental Delivery

1. US1 restores observable logging behavior without new public contracts.
2. US2 verifies ownership, literal class compatibility, SQL parameters/results, original errors, cleanup, and controlled recovery.
3. US3 verifies the same assertions across both distributions plus real SQL and supported hosts.
4. Finish documentation, analysis, and requirement evidence. Keep unavailable checks explicitly outstanding; do not equate zero reported failures with complete discovery or successful release validation.

## Requirement Coverage

| Requirement | Primary tasks |
|---|---|
| FR-001, FR-002: helper identity, inventory, dependencies | T004, T009, T013, T019–T020 |
| FR-003: logging streams, formatting, invocation preferences | T007–T012 |
| FR-004: retained exact-one audit regression | T001, T006, T012, T028 |
| FR-005: archiving logging and local SQL/cleanup | T007–T011, T014–T017, T019 |
| FR-006: public/runtime/platform contract | T002, T021, T027–T029 |
| FR-007: existing class consumers | T010, T016, T019, T028–T029 |
| FR-008: SQL, state, configuration, order, retry | T014, T017–T018, T022–T028 |
| FR-009: resource cleanup, constraints, primary errors | T015, T017–T020, T022–T028 |
| FR-010: full source/package matrix | T004–T005, T008, T013, T019–T029 |
| SC-001–SC-005: complete behavioral outcomes | T012, T020–T029, T032 |

**Task totals**: 32 tasks: Setup 3, Foundational 2, US1 7, US2 8, US3 9, Polish 3. Parallel markers identify 18 tasks in the ready groups above. Implementation status: 31 tasks completed; T029 remains open for Windows/macOS host execution. See validation.md and evidence/ for measured results.
