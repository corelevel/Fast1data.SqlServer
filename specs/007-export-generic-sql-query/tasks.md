---
description: "Implementation tasks for exporting generic SQL commands and streaming migration history"
---

# Tasks: Export Generic SQL Commands

**Input**: Design documents from `specs/007-export-generic-sql-query/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/public-commands.md`, `contracts/migration-history.md`, `quickstart.md`, and `.specify/memory/constitution.md`.

**Tests**: Included because the specification explicitly requires query, parameter, cleanup, module-loading, and migration regression verification. Add the relevant acceptance tests before implementation and confirm that new behavior fails for the expected reason. Preserve existing coverage.

**Organization**: The specification contains agreed decisions and acceptance checks rather than numbered, prioritized user stories. The following story labels and priorities are task-planning groupings of that contract, not new specification requirements:

| Story | Priority | Contract covered |
|---|---|---|
| US1 | P1 | Public scalar/silent non-query execution and public typed parameter construction |
| US2 | P1 | Incremental first-tabular-result row output with safe ownership and exports |
| US3 | P2 | Migration-history retrieval through the row command with exact persisted keys |

**Implementation gate**: Generating this file does not satisfy the specification's final confirmation gate. T001 must be satisfied before production implementation begins.

## Format: `[ID] [P?] [Story] Description`

- Every task uses an unchecked checkbox, sequential ID, and exact repository-relative file paths.
- `[P]` identifies tasks that can run concurrently within the stated phase after its prerequisites; their edited files do not overlap.
- `[US1]`, `[US2]`, and `[US3]` apply only to story phases.

## Path Conventions

- Source, manifest, and tests live under `Fast1data.SqlServer/`.
- Shared behavior remains in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`; the existing root and model loaders keep independently defined shared functions.
- The factory lives in `Fast1data.SqlServer/public/New-Fast1GenericSqlParam.ps1`.
- Feature acceptance evidence is recorded in `specs/007-export-generic-sql-query/quickstart.md`; root guidance lives in `README.md` and `Fast1Migration.md`.
- No new dependencies, runtime baseline, schema, or configuration format are needed.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish authorization and a reproducible implementation baseline.

- [X] T001 Verify the maintainer's final confirmation of the complete contract and record the confirmed implementation status in `specs/007-export-generic-sql-query/spec.md`; if confirmation is absent from session context, obtain it before any production edits, as required by that file's Remaining gate.
- [X] T002 Record the initial runtime/platform, Pester/PSScriptAnalyzer availability, bundled-assembly availability, applicable analyzer settings, and baseline affected offline-suite outcomes in `specs/007-export-generic-sql-query/quickstart.md`; note availability of the opt-in SQL environment without printing its connection string, and retain PowerShell 7.6+, .NET 10 build targets, and existing dependency versions.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish reusable controlled resources and one compatible parameter-binding path.

**Blocking rule**: Complete this phase before story implementation. SQL reader behavior is implemented in US2, not in the foundation.

- [X] T003 Add reusable controlled command/reader fixtures in `Fast1data.SqlServer/tests/fixtures/GenericSqlQuery.Doubles.ps1`, bootstrapped through the existing `Fast1data.SqlServer/tests/fixtures/Import-SharedHelperDependency.ps1` pattern; support ordered result metadata, native ordinal values, read/output event tracing, result navigation, disposal tracing, and injectable operation/disposal failures without redefining the descriptor class or adding production seams.
- [X] T004 Extend `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` before changing the descriptor/binder: update the intentional Type reflection expectation to nullable SqlDbType, distinguish uninitialized/null Type from explicit BigInt/zero, retain cast-hashtable construction in root/model scopes, and cover wrong descriptors, typed nulls, positive/zero metadata, silent binding, and zero-/one-/multi-byte parameter arrays; confirm relevant new assertions fail on current code.
- [X] T005 Change only Type to nullable System.Data.SqlDbType in `Fast1data.SqlServer/private/shared/GenericSqlParam.psm1`, preserving the existing class identity and other fields; enforce the model rule "Required by factory; null rejected by both executors; BigInt/zero accepted." while leaving uninitialized private descriptor Type null and existing cast-hashtable construction valid.
- [X] T006 Extract one private parameter-binding helper in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1` and route existing scalar/non-query execution through it; use descriptor/null validation rather than enum truthiness, bind explicit SqlDbType with keys lacking `@`, and emit no helper output. Preserve "Null binds to DBNull.Value; other values retain native representation, including byte arrays.", "New factory accepts 0 through Int32.MaxValue; only positive values are forwarded.", Precision's "Positive values forwarded; zero leaves provider default.", and Scale's "Positive values forwarded; zero leaves provider default, including inference." through direct value assignment and separate null handling; retain command disposal, original errors, execution defaults, and borrowed-connection ownership, then pass T004.

**Checkpoint**: BigInt and typed nulls work through the existing executor in both defining scopes; genuinely missing types fail; only the existing class and shared loading mechanism are used.

---

## Phase 3: User Story 1 - Public scalar execution and typed parameters (Priority: P1) MVP

**Goal**: A caller using only a root module import can create typed parameters and execute scalar or silent non-query SQL without knowing the private class path.

**Independent Test**: In fresh processes, import the manifest and direct root module, create BigInt and typed-null descriptors through `New-Fast1GenericSqlParam`, and exercise scalar and non-query behavior. The first increment exposes five commands (the original three plus the existing query and factory); US2 completes the agreed six-command surface. Existing command metadata remains identical.

### Tests for User Story 1

- [X] T007 [P] [US1] Create factory/public-caller contract tests in `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1`: normal root import without `using module` or private class lookup, exactly one descriptor and no SQL allocation, mandatory explicit Type tested noninteractively, rejection of explicit null/invalid Type, BigInt by name/zero, omitted/explicit-null Value, native binary values, Size zero/Int32.MaxValue and negative rejection, and byte Precision/Scale boundaries with zero defaults.
- [X] T008 [P] [US1] Extend existing execution tests in `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` for scalar first-cell/empty/DBNull compatibility, silent non-query output, factory-produced descriptors, StoredProcedure input binding, unchanged provider timeout, and construction/binding/execution/cleanup failures with primary-error retention; enforce SqlConn's "Borrowed, already open; never opened, closed, or disposed by query commands." and reject closed/invalid connections without opening or repairing them.
- [X] T009 [P] [US1] Extend fresh-process public-contract checks in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1`, and `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json` for the five-command US1 increment, testing direct `.psm1` and manifest imports, public factory usability, unchanged original three command metadata, private binder/construction/cleanup functions, and empty nested-module exports; preserve the existing snapshot entries exactly.

### Implementation for User Story 1

- [X] T010 [US1] Implement `Fast1data.SqlServer/public/New-Fast1GenericSqlParam.ps1` to return the existing descriptor with required validated Type and optional Value/Size/Precision/Scale; implement "Required by factory; null rejected by both executors; BigInt/zero accepted.", "Null binds to DBNull.Value; other values retain native representation, including byte arrays.", "New factory accepts 0 through Int32.MaxValue; only positive values are forwarded.", "Positive values forwarded; zero leaves provider default.", and "Positive values forwarded; zero leaves provider default, including inference." without adding presence flags, MAX size -1, output parameters, or a second class identity.
- [X] T011 [US1] Update `Fast1data.SqlServer/Fast1data.SqlServer.psm1` to explicitly export the existing shared `Invoke-Fast1GenericSqlQuery` alongside public-file commands and update FunctionsToExport in `Fast1data.SqlServer/Fast1data.SqlServer.psd1` to the five US1 commands; keep the query definition in shared behavior and avoid wrappers, wildcard exports, or new nested modules.
- [X] T012 [US1] Complete comment help for `New-Fast1GenericSqlParam` in `Fast1data.SqlServer/public/New-Fast1GenericSqlParam.ps1` and `Invoke-Fast1GenericSqlQuery` in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`, including inputs/outputs/examples, caller connection ownership, typed SQL NULL, native values, positive-only metadata, unchanged scalar DBNull behavior, silent non-query execution, and timeout defaults; retain Query's "Mandatory SQL text or procedure name; executable administrator input.", CommandType's "Text by default; existing StoredProcedure usage retained.", Parameters' "Optional typed descriptors.", and Scalar's "First-column/first-row provider result; absent means silent non-query."
- [X] T013 [US1] Run the US1-focused query/cleanup and fresh-process loader/shared-import checks described in `specs/007-export-generic-sql-query/quickstart.md`, adjusting the expected worker count in `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` only to the actual changed test count; record five-export import results and public-factory/scalar/non-query evidence, with unavailable checks explicitly unverified.

**Checkpoint**: Public typed parameter construction and scalar/silent non-query execution are independently usable and verified; this is the suggested MVP, with final six-command acceptance still pending US2.

---

## Phase 4: User Story 2 - Stream the first tabular result (Priority: P1)

**Goal**: Emit independent ordered row objects incrementally, preserve native values, and reliably release owned readers/commands while leaving the caller's connection open.

**Independent Test**: Verify zero/one/many rows, leading non-tabular results, an empty first tabular result followed by populated results, invalid schemas even when empty, native/null/binary values, output before the next read, partial output after failure, and early termination with connection reuse. Both import forms expose exactly six commands.

### Tests for User Story 2

- [X] T014 [P] [US2] Extend `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1` using the controlled fixtures for the row command's signature (same SqlConn/Query/CommandType/Parameters, no Scalar/Rows switch), factory/shared-binder compatibility, zero/one/many rows, no tabular result, leading non-tabular results, first empty tabular result stopping selection, ignored later results, ordinal property order, fresh independent objects, numeric/date/null values, and zero-/one-/multi-byte arrays; reject blank/whitespace and ordinal case-insensitive duplicate names before Read/output, including empty schemas, with alias guidance.
- [X] T015 [P] [US2] Add deterministic streaming and failure tests in `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` for root/model row execution: first output precedes second Read, later Read failure retains prior output, `Select-Object -First 1` stops further application reads, and construction/binding/ExecuteReader/NextResult/schema/GetValue/Read failures release all created resources. Verify reader-then-command disposal, untouched borrowed connection, primary-error preservation, cleanup-only failure, and combined disposal failures with safe `Fast1Sql.CleanupFailures` details.
- [X] T016 [P] [US2] Create `Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1`, gated by nonblank `FAST1_TEST_MIGRATION_SQL_CONN_STR`, using its own uniquely named disposable database with guarded teardown and no secret output; cover real empty/multiple/non-tabular results, aliases/invalid empty-result names, numeric/date/null/binary values, BigInt/typed-null parameters, StoredProcedure inputs, scalar/non-query compatibility, provider failures, and early termination followed by successful reuse of the still-open connection. Keep deterministic late-read/disposal injection in offline tests rather than inferring timing from SQL batches.
- [X] T017 [P] [US2] Extend `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`, `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1`, `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Classes.ps1`, `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json`, and `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` for exactly six exports, row/binder defining ownership in root and model, root-only factory, preserved descriptor identity, empty nested-module exports, unchanged original public metadata, and existing import-order/force-reimport scenarios; include the focused offline query suite in worker containers and recalculate expected totals from actual cases when running the matrix.

### Implementation for User Story 2

- [X] T018 [US2] Implement `Invoke-Fast1GenericSqlQueryReader` beside the existing executor in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`, sharing typed binding and existing defaults; use default ExecuteReader without CloseConnection, skip only leading FieldCount-zero results, select the first result with columns even if empty, and never advance afterward. Enforce "Names must be nonblank and unique with ordinal case-insensitive comparison." before Read, preserve accepted names/order, and emit one fresh ordered PSCustomObject from direct GetValue assignments per read, replacing only DBNull with null and retaining byte arrays without buffering the full result or leaking reader/metadata objects.
- [X] T019 [US2] Apply the existing operation-error/try/finally cleanup pattern to the row command in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`, calling `Close-GenericSqlResource` with ordered reader then command resources; pass T015 for success, operation failure, partial output, downstream termination, and combined cleanup failures without opening/disposing the connection, draining rows in the application loop, automatic cancellation, or adding SQL/value data to cleanup annotations.
- [X] T020 [US2] Complete root and manifest exports in `Fast1data.SqlServer/Fast1data.SqlServer.psm1` and `Fast1data.SqlServer/Fast1data.SqlServer.psd1` with `Invoke-Fast1GenericSqlQueryReader`, exposing exactly Invoke-Fast1Audit, Invoke-Fast1Migration, Invoke-Fast1Archiving, Invoke-Fast1GenericSqlQuery, Invoke-Fast1GenericSqlQueryReader, and New-Fast1GenericSqlParam; retain both query definitions in the existing independently loaded shared file and keep the binder private.
- [X] T021 [US2] Add full row-command comment help in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1` covering typed inputs, ordered native properties, SQL NULL, distinct aliases, first-tabular-result/empty-result behavior, incremental output and partial failures, reader/command versus connection ownership, provider disposal latency, and the possibility that later SQL statements execute; state that whole individual values can be materialized and do not promise cancellation, rollback, or atomic output.
- [X] T022 [US2] Run the row/factory/cleanup suites, source direct/manifest imports, and updated shared-scope matrix; run the public SQL smoke scenario and new live query suite when the explicitly configured environment is available, and record counts, six-export evidence, connection reuse, skips, and unavailable checks in `specs/007-export-generic-sql-query/quickstart.md`.

**Checkpoint**: The final public surface is complete; row behavior and ownership are independently testable before migration-history integration.

---

## Phase 5: User Story 3 - Delegate migration-history reads (Priority: P2)

**Goal**: Reuse the streaming public row command internally while preserving private history contracts, exact persisted keys, and outer connection ownership.

**Independent Test**: Observe Get-Executed delegating the exact history SELECT and NVarChar(32) phase descriptor on its own open connection, returning zero or more unchanged script_name/checksum rows. Verify reader-command-connection disposal order on success, failure, and truncation, then retain forced legacy-key updates and existing migration behavior in offline and live checks.

### Tests for User Story 3

- [X] T023 [P] [US3] Add focused delegation/output tests in `Fast1data.SqlServer/tests/Migration.Tests.ps1` for unchanged private mandatory ConnStr/Phase inputs, the exact SELECT/filter in `specs/007-export-generic-sql-query/contracts/migration-history.md`, factory invocation with NVarChar/Size 32/Phase, open delegated connection and Text command type, empty/populated history, direct streaming, original spelling/case/slash/backslash keys, and unchanged checksums/property order; phase is "Bound filter, not an output property."
- [X] T024 [P] [US3] Update Get-Executed's existing owned-resource assertions in `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` from direct reader/command/connection ownership to connection-only ownership, and add nested real-row-command cleanup tests for reader-command-connection order on success, open/reader/schema/read failure, partial output, and downstream truncation; verify connection disposal after inner cleanup and preservation of combined inner/outer safe cleanup details, including cleanup-only errors and connection construction/open failures.
- [X] T025 [P] [US3] Extend targeted history-read acceptance in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` for empty history, exact persisted legacy names/checksums, and the delegated row path; preserve existing original-key forced update tests including the case-sensitive disposable database, checksum/skip timestamps, idempotent retry, failure stopping, and WhatIf cases without rewriting phase evaluation or changing history schema.

### Implementation for User Story 3

- [X] T026 [US3] Refactor only history retrieval in `Fast1data.SqlServer/private/migration/Get-Executed.ps1`: retain ConnStr/Phase and owned connection initialization/opening, preserve the contract's exact SQL, construct `New-Fast1GenericSqlParam -Type NVarChar -Size 32 -Value $Phase -WhatIf:$false -Confirm:$false`, and stream `Invoke-Fast1GenericSqlQueryReader` directly with the phase hashtable. Remove local command/reader/binding/row-loop code, preserve "Bound filter, not an output property.", "Preserve exact stored spelling/case/separators.", and "Return unchanged after script_name.", and retain operation-error capture with connection-only cleanup after inner unwinding.
- [X] T027 [US3] Update Get-Executed comment help in `Fast1data.SqlServer/private/migration/Get-Executed.ps1` and history guidance in `Fast1Migration.md` for row delegation, exact stored keys, streaming/partial failure, owned connection versus inner reader/command cleanup, and unchanged order/checksum/force/ignore/preview/retry semantics; retain idempotent migration guidance and avoid connection-string secrets in examples.
- [X] T028 [US3] Run `Fast1data.SqlServer/tests/Migration.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1`, and `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1`, plus `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` when the explicit SQL environment is available; record delegation, persisted-key, retry/preview, nested-cleanup results and actual skips in `specs/007-export-generic-sql-query/quickstart.md`.

**Checkpoint**: History retrieval reuses the public row command without altering persisted migration identity or execution behavior.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Complete documentation and constitution-required source/package/platform acceptance.

- [X] T029 [P] Update command/help listings and runnable usage examples in `README.md` for all six exports, ordinary root import, typed BigInt and SQL NULL, open/dispose connection lifecycle, parameter names without `@`, scalar/silent non-query calls, streamed CSV output, distinct aliases, first-empty-result semantics, metadata limits, partial errors, and later-statement/disposal behavior; use secret-free placeholders and retain prerequisites and existing command guidance.
- [X] T030 [P] Update current 0.1.0 release notes in `Fast1data.SqlServer/Fast1data.SqlServer.psd1` for the additive three-command public surface, nullable private descriptor Type/BigInt fix, and history delegation; retain release version, PowerShell baseline, existing bundled dependency versions, and runtime asset declarations.
- [X] T031 Run Invoke-ScriptAnalyzer over every modified `.ps1`, `.psm1`, and `.psd1`, including tests/fixtures and manifest, using project settings when available and tab-indented multiline control-flow blocks; resolve all new warnings/errors without suppression, report unrelated existing findings or unavailable analyzer explicitly, and record file coverage/results in `specs/007-export-generic-sql-query/quickstart.md`.
- [X] T032 Reconcile expected worker totals in `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` with the final actual test inventory, preserving rejection of unexpected skips; run the affected final offline query/cleanup/migration/module-loader/shared-import suites and fresh-process direct/manifest imports from `specs/007-export-generic-sql-query/quickstart.md`, verify exactly six exports and unchanged original command metadata, and record source results. Reanalyze the worker if edited after T031.
- [X] T033 Run `out/publish.ps1 -StageOnly` after source checks pass, inspect analyzer output as well as exit status, and validate fresh-process staged `.psd1`/`.psm1` imports, public factory/query usability, and staged query/module-loader/shared-import suites under `out/Fast1data.SqlServer/tests/`; verify packaged runtime assets and record staged results separately in `specs/007-export-generic-sql-query/quickstart.md` without changing publishing behavior.
- [X] T034 Complete the acceptance record in `specs/007-export-generic-sql-query/quickstart.md` against `specs/007-export-generic-sql-query/spec.md` and both `specs/007-export-generic-sql-query/contracts/public-commands.md` and `specs/007-export-generic-sql-query/contracts/migration-history.md`: record live query/migration outcomes and native x64 Windows/Linux/macOS import/smoke evidence when those environments are available, including commands/runtime/counts/skips; label unavailable live/native checks unverified, keep source/staged evidence distinct, and identify any material unresolved resource or migration-integrity failure as release-blocking rather than claiming acceptance.

---

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1: Setup + existing confirmation gate
    |
    v
Phase 2: Fixtures + nullable descriptor + shared binder
    |
    v
US1 (P1): Public query + parameter factory [MVP; five exports]
    |
    v
US2 (P1): Streaming rows [final six exports]
    |
    v
US3 (P2): Migration-history delegation
    |
    v
Phase 6: Documentation + analyzer + source/staged/native/live acceptance
```

- **Setup**: T001 is the existing production-implementation gate; T002 establishes the baseline before changing behavior.
- **Foundation**: T003 enables controlled-resource tests; T004 precedes T005/T006; T005 enables genuine missing-Type validation in T006. All stories depend on T006.
- **US1**: T007-T009 are independent test-authoring tasks after foundation. T010 precedes the public export change T011. T012 completes help before T013 validates the increment. Adjust test-worker expected counts only when the test inventory changes.
- **US2**: Depends on US1's public factory and export pattern. T014-T017 can be authored together. T018 uses the shared binder; T019 completes its resource lifecycle; T020 exposes the implemented function; T021 completes help; T022 validates the increment. T017's worker execution waits for implementation and final observed counts, even though its test edits can be parallelized.
- **US3**: Depends on US1's factory and US2's row command. T023-T025 can be authored together, then T026 implements delegation; T027/T028 document and verify the increment.
- **Polish**: T029/T030 can run together after story completion. T031-T034 proceed in order; analyzer coverage must include any later PowerShell edits.

### Within Each User Story

- Write acceptance tests first and confirm expected missing-behavior failures; do not treat missing environments as a failing feature test or a passing check.
- Complete implementation and ownership behavior before the story checkpoint.
- Story tests can be run independently after their prerequisite increments; shared implementation files mean the stories themselves are sequenced.
- Do not normalize migration keys in Get-Executed, change phase evaluation, add public options, alter provider defaults, or broaden nested-module exports.

### Parallel Opportunities

- US1: T007, T008, and T009 edit separate test files.
- US2: T014, T015, T016, and T017 edit separate test/fixture groups.
- US3: T023, T024, and T025 edit separate test suites.
- Polish: T029 and T030 edit separate documentation/manifest files.
- Serialize production changes to `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`, root/manifest exports, and shared snapshots across phases; no cross-story production parallelism is assumed.

---

## Parallel Example: User Story 1

After Phase 2, author these tests concurrently, then run them before T010/T011:

```text
T007: Factory/public-caller tests in Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1
T008: Existing execution/ownership tests in Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1
T009: Five-export compatibility tests and public snapshot in loader/shared-helper fixtures
```

## Parallel Example: User Story 2

After US1, author these independent test groups before implementing the row command:

```text
T014: Row/schema/native-value tests in Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1
T015: Streaming/failure/disposal tests in Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1
T016: Provider tests in Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1
T017: Six-export/scope/class-identity tests in module-loader/shared-helper fixtures
```

## Parallel Example: User Story 3

After US2, author these independent history test groups before T026:

```text
T023: Delegation and exact output in Fast1data.SqlServer/tests/Migration.Tests.ps1
T024: Nested ownership/errors in Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1
T025: Persisted behavior in Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Satisfy the existing confirmation gate and record the baseline.
2. Complete nullable descriptor/shared binding prerequisites.
3. Complete US1 tests, factory, public scalar/non-query export, help, and independent verification.
4. Validate the five-command increment; the full feature still requires the streaming command and migration integration.

### Incremental Delivery

1. Deliver US1 as the smallest independently useful public API increment.
2. Deliver US2 and validate streaming, partial errors, disposal, and the final six-command surface through controlled and real-provider checks.
3. Deliver US3 while retaining exact persisted keys and migration regression coverage.
4. Complete documentation, changed-file analysis, source/staged checks, and available native/live acceptance; record every unverified environment explicitly.

### Notes

- This checklist defines implementation work; no production implementation or feature acceptance is claimed by task generation.
- New test fixtures remain test-only. Reuse existing cleanup and loader architecture instead of adding dependencies or public helpers.
- Live suites require the explicitly selected test SQL environment and disposable fixture databases; never commit or print credentials.
- Native Windows/Linux/macOS verification requires those hosts. Missing hosts or skipped SQL suites remain unverified and must be visible in the acceptance record.
