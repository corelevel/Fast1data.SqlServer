---
description: "Completed generic SQL commands and public-file relocation tasks"
---

# Tasks: Export Generic SQL Commands

**Input**: Design documents from `specs/007-export-generic-sql-query/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/public-commands.md`, `contracts/migration-history.md`, `contracts/command-loading.md`, `quickstart.md`, and `.specify/memory/constitution.md`.

**Tests**: Included because the specification explicitly requires query, parameter, cleanup, module-loading, and migration regression verification. Add the relevant acceptance tests before implementation and confirm that new behavior fails for the expected reason. Preserve existing coverage.

**Current scope (2026-11-20)**: Append the public-file relocation amendment without reopening the preceding implementation. T001-T034 remain checked historical records; their old source-location/export instructions are superseded by FR-001 through FR-006. Execute only the unchecked T035-T056 below. Historical US labels apply only to the historical phases; current labels map directly to the revised specification:

| Story | Priority | Contract covered |
|---|---|---|
| US1 | P1 | Locate each public command by name: canonical public definitions and help |
| US2 | P1 | Continue using existing command contracts: imports, exports, scopes, SQL behavior, migration and archiving |

**Authorization and evidence**: T001 records the prior confirmation; it is not a new approval gate. T035–T056 were executed by the implementation invocation; relocation evidence is recorded separately in quickstart.md. The six historical migration-input failures were reassessed and did not reproduce. Current Windows SQL acceptance and audit reruns passed; native Linux/macOS checks remain unverified. The full-suite rerun and the original setup failures are recorded in quickstart.md; no passing all-platform release is claimed.

## Format: `[ID] [P?] [Story] Description`

- New amendment tasks use unchecked checkboxes, sequential IDs continuing after T034, and exact repository-relative file paths. Completed historical tasks retain their checked status.
- `[P]` identifies tasks that can run concurrently within the stated phase after its prerequisites; their edited files do not overlap.
- Current `[US1]` and `[US2]` labels apply only to amendment story phases. Historical `[US3]` is retained solely as preceding implementation history.

## Path Conventions

- Source, manifest, and tests live under `Fast1data.SqlServer/`.
- Private binder/command construction remain in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`; query definitions/help move to `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQuery.ps1` and `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQueryReader.ps1`, independently loaded into root and model scopes.
- The factory lives in `Fast1data.SqlServer/public/New-Fast1GenericSqlParam.ps1`.
- Feature acceptance evidence is recorded in `specs/007-export-generic-sql-query/quickstart.md`; root guidance lives in `README.md` and `Fast1Migration.md`.
- No new dependencies, runtime baseline, schema, or configuration format are needed.

## Historical Phase 1: Setup (Completed)

**Purpose**: Establish authorization and a reproducible implementation baseline.

- [X] T001 Verify the maintainer's final confirmation of the complete contract and record the confirmed implementation status in `specs/007-export-generic-sql-query/spec.md`; if confirmation is absent from session context, obtain it before any production edits, as required by that file's Remaining gate.
- [X] T002 Record the initial runtime/platform, Pester/PSScriptAnalyzer availability, bundled-assembly availability, applicable analyzer settings, and baseline affected offline-suite outcomes in `specs/007-export-generic-sql-query/quickstart.md`; note availability of the opt-in SQL environment without printing its connection string, and retain PowerShell 7.6+, .NET 10 build targets, and existing dependency versions.

---

## Historical Phase 2: Foundational (Completed)

**Purpose**: Establish reusable controlled resources and one compatible parameter-binding path.

**Blocking rule**: Complete this phase before story implementation. SQL reader behavior is implemented in US2, not in the foundation.

- [X] T003 Add reusable controlled command/reader fixtures in `Fast1data.SqlServer/tests/fixtures/GenericSqlQuery.Doubles.ps1`, bootstrapped through the existing `Fast1data.SqlServer/tests/fixtures/Import-SharedHelperDependency.ps1` pattern; support ordered result metadata, native ordinal values, read/output event tracing, result navigation, disposal tracing, and injectable operation/disposal failures without redefining the descriptor class or adding production seams.
- [X] T004 Extend `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` before changing the descriptor/binder: update the intentional Type reflection expectation to nullable SqlDbType, distinguish uninitialized/null Type from explicit BigInt/zero, retain cast-hashtable construction in root/model scopes, and cover wrong descriptors, typed nulls, positive/zero metadata, silent binding, and zero-/one-/multi-byte parameter arrays; confirm relevant new assertions fail on current code.
- [X] T005 Change only Type to nullable System.Data.SqlDbType in `Fast1data.SqlServer/private/shared/GenericSqlParam.psm1`, preserving the existing class identity and other fields; enforce the model rule "Required by factory; null rejected by both executors; BigInt/zero accepted." while leaving uninitialized private descriptor Type null and existing cast-hashtable construction valid.
- [X] T006 Extract one private parameter-binding helper in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1` and route existing scalar/non-query execution through it; use descriptor/null validation rather than enum truthiness, bind explicit SqlDbType with keys lacking `@`, and emit no helper output. Preserve "Null binds to DBNull.Value; other values retain native representation, including byte arrays.", "New factory accepts 0 through Int32.MaxValue; only positive values are forwarded.", Precision's "Positive values forwarded; zero leaves provider default.", and Scale's "Positive values forwarded; zero leaves provider default, including inference." through direct value assignment and separate null handling; retain command disposal, original errors, execution defaults, and borrowed-connection ownership, then pass T004.

**Checkpoint**: BigInt and typed nulls work through the existing executor in both defining scopes; genuinely missing types fail; only the existing class and shared loading mechanism are used.

---

## Historical Phase 3: Former US1 - Public scalar execution and typed parameters (Completed)

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

## Historical Phase 4: Former US2 - Stream the first tabular result (Completed)

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

## Historical Phase 5: Former US3 - Delegate migration-history reads (Completed)

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

## Historical Phase 6: Polish & Cross-Cutting Concerns (Completed)

**Purpose**: Complete documentation and constitution-required source/package/platform acceptance.

- [X] T029 [P] Update command/help listings and runnable usage examples in `README.md` for all six exports, ordinary root import, typed BigInt and SQL NULL, open/dispose connection lifecycle, parameter names without `@`, scalar/silent non-query calls, streamed CSV output, distinct aliases, first-empty-result semantics, metadata limits, partial errors, and later-statement/disposal behavior; use secret-free placeholders and retain prerequisites and existing command guidance.
- [X] T030 [P] Update current 0.1.0 release notes in `Fast1data.SqlServer/Fast1data.SqlServer.psd1` for the additive three-command public surface, nullable private descriptor Type/BigInt fix, and history delegation; retain release version, PowerShell baseline, existing bundled dependency versions, and runtime asset declarations.
- [X] T031 Run Invoke-ScriptAnalyzer over every modified `.ps1`, `.psm1`, and `.psd1`, including tests/fixtures and manifest, using project settings when available and tab-indented multiline control-flow blocks; resolve all new warnings/errors without suppression, report unrelated existing findings or unavailable analyzer explicitly, and record file coverage/results in `specs/007-export-generic-sql-query/quickstart.md`.
- [X] T032 Reconcile expected worker totals in `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` with the final actual test inventory, preserving rejection of unexpected skips; run the affected final offline query/cleanup/migration/module-loader/shared-import suites and fresh-process direct/manifest imports from `specs/007-export-generic-sql-query/quickstart.md`, verify exactly six exports and unchanged original command metadata, and record source results. Reanalyze the worker if edited after T031.
- [X] T033 Run `out/publish.ps1 -StageOnly` after source checks pass, inspect analyzer output as well as exit status, and validate fresh-process staged `.psd1`/`.psm1` imports, public factory/query usability, and staged query/module-loader/shared-import suites under `out/Fast1data.SqlServer/tests/`; verify packaged runtime assets and record staged results separately in `specs/007-export-generic-sql-query/quickstart.md` without changing publishing behavior.
- [X] T034 Complete the acceptance record in `specs/007-export-generic-sql-query/quickstart.md` against `specs/007-export-generic-sql-query/spec.md` and both `specs/007-export-generic-sql-query/contracts/public-commands.md` and `specs/007-export-generic-sql-query/contracts/migration-history.md`: record live query/migration outcomes and native x64 Windows/Linux/macOS import/smoke evidence when those environments are available, including commands/runtime/counts/skips; label unavailable live/native checks unverified, keep source/staged evidence distinct, and identify any material unresolved resource or migration-integrity failure as release-blocking rather than claiming acceptance.

---

## Amendment Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a current baseline and a bounded acceptance map before changing source files.

- [X] T035 Record a fresh relocation baseline in `specs/007-export-generic-sql-query/quickstart.md`: run its section 2 source suites before edits; record runtime, Pester/analyzer/settings and bundled-asset availability, observed counts/skips, the actual six migration-input failures if still present, and availability of the opt-in SQL environment without printing its value. Preserve the preceding evidence as history.
- [X] T036 Map FR-001 through FR-006 and SC-001 through SC-003 to amendment checks in `specs/007-export-generic-sql-query/quickstart.md` using `specs/007-export-generic-sql-query/contracts/command-loading.md`; record the current 23-private-file inventory, three shared entries, 16 ownership observations, six-command snapshot and 249-case worker inventory as baselines to verify, not totals to loosen.

---

## Amendment Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Prepare the existing fresh-process harness for the new required public dependencies.

- [X] T037 Verify and extend only as needed `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1` so disposable-copy fault injection accepts either public query path with Missing, Corrupt (parse-invalid) and RuntimeError faults for Root and Model consumers; bootstrap standalone model SqlClient through the existing designated loader, capture prior/restored error preference, actionable path/stage and original inner errors, and failed initialization without exposing public commands. Keep fault targets within the disposable distribution and retain selected-assembly checks; add no production seam.

**Checkpoint**: Fault/ownership observations can express the amendment contract. All subsequent story work depends on this phase. No new package, descriptor class, schema, runtime baseline or generic loading framework is needed.

---

## Amendment Phase 3: User Story 1 - Locate each public command by name (Priority: P1) MVP

**Goal**: Each new public command has one canonical matching public file containing its definition and complete help; private support stays private.

**Independent Test**: Run focused AST layout checks for all three public files and recursively inspect `private/shared`. Require exact spelling, one matching top-level function per file, discoverable complete comment help and zero duplicate/forwarding public definitions. This is the smallest reviewable layout increment; release still requires US2 compatibility and package acceptance.

### Tests for User Story 1

- [X] T038 [US1] Add AST layout acceptance cases to `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1` for `public/Invoke-Fast1GenericSqlQuery.ps1`, `public/Invoke-Fast1GenericSqlQueryReader.ps1` and `public/New-Fast1GenericSqlParam.ps1` under the selected distribution; require exact filename/function spelling, a matching top-level definition with synopsis/description/parameter/output/example help, no duplicate or forwarding definition anywhere in `private/shared`, and only Add-GenericSqlParameter/Get-GenericSqlCommand in the private query support file. Confirm the missing public query files fail before relocation.

### Implementation for User Story 1

- [X] T039 [US1] Move the complete existing executor and reader function/help blocks intact from `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1` into `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQuery.ps1` and `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQueryReader.ps1`; retain only Add-GenericSqlParameter/Get-GenericSqlCommand in private support, preserve `Fast1data.SqlServer/public/New-Fast1GenericSqlParam.ps1` and its literal class import, and add no wrappers, duplicate definitions, class imports or execution-body changes.
- [X] T040 [US1] Run the focused layout cases in `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1` and record exact public paths, help presence, private-only support and zero duplicates in `specs/007-export-generic-sql-query/quickstart.md`; compare the moved function bodies/help to the baseline and record compatibility checks as pending until US2.

**Checkpoint**: FR-001/FR-002 and SC-001 have direct layout evidence. The root/model integration follows immediately before broader runtime acceptance.

---

## Amendment Phase 4: User Story 2 - Continue using the existing command contracts (Priority: P1)

**Goal**: Preserve the six-command API and independent root/model operation through source and packaged imports, including query, cleanup, history and archiving behavior.

**Independent Test**: Fresh manifest/direct imports and standalone model-first/root-first loads use only the selected distribution, export exactly six root commands and no nested commands, and resolve both query functions to exact public source paths in independent session states. Existing offline/live query, cleanup, migration and archiving checks retain their behavior; repeat affected checks against the staged distribution in T054.

### Tests for User Story 2

- [X] T041 [P] [US2] Extend `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` to assert both literal model public dot-sources after shared support, root public-loop/basename exports, unchanged three-entry shared loader, complete 23-file private coverage and two separately counted public dependencies; add all 12 public-query fault combinations (two files × two consumers × Missing/Corrupt/RuntimeError) using T037. Require terminating initialization, restored preference, original error/path context and no successful root exports; confirm the new model dependency assertions fail before loader implementation.
- [X] T042 [P] [US2] Strengthen ownership checks in `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1` and `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1` to compare each query's ScriptBlock.File with its exact matching public path under DistributionRoot, retaining distinct root/model Module and SessionState owners, eight functions per consumer (16 observations), root-only factory, existing descriptor identity and empty nested exports; retain the unchanged `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json` six-command metadata snapshot. Exercise standalone model-first/root-first and unrelated-working-directory imports; confirm missing model-local public provenance fails before implementation.

### Implementation and Regression Verification for User Story 2

- [X] T043 [US2] Simplify `Fast1data.SqlServer/Fast1data.SqlServer.psm1` to export only $publicScripts.BaseName after its existing discovery loop, removing appended query names; preserve bootstrap/load ordering and initialization error handling, load each public file only through that loop, and retain exactly the six explicit FunctionsToExport entries and current version/runtime declarations in `Fast1data.SqlServer/Fast1data.SqlServer.psd1`.
- [X] T044 [US2] Add literal $PSScriptRoot-anchored dot-sources for `../../public/Invoke-Fast1GenericSqlQuery.ps1` and `../../public/Invoke-Fast1GenericSqlQueryReader.ps1` in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` inside its existing dependency try immediately after shared support; preserve error wrapping/preference restoration, existing class imports and empty exports. Leave `Fast1data.SqlServer/private/shared/Load.ps1` unchanged; do not enumerate other public files, load the factory into the model or require root import. Pass T041/T042 for both consumers.
- [X] T045 [US2] Run existing factory/binder regressions in `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1` and `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1`, preserving the data-model rules verbatim: Type "Required by factory; null rejected by both executors; BigInt/zero accepted.", Value "Null binds to DBNull.Value; other values retain native representation, including byte arrays.", Size "New factory accepts 0 through Int32.MaxValue; only positive values are forwarded.", Precision "Positive values forwarded; zero leaves provider default.", and Scale "Positive values forwarded; zero leaves provider default, including inference." Retain int Size, byte Precision/Scale, zero metadata defaults, nullable private Type, normal one-descriptor output and WhatIf no-output behavior; add coverage only for a demonstrated gap and record outcomes in `specs/007-export-generic-sql-query/quickstart.md`.
- [X] T046 [US2] Run existing query/streaming/cleanup regressions in `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1` and `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` for both scopes, preserving SqlConn "Borrowed, already open; never opened, closed, or disposed by query commands.", Query "Mandatory SQL text or procedure name; executable administrator input.", CommandType "Text by default; existing StoredProcedure usage retained.", Parameters "Optional typed descriptors.", Scalar "First-column/first-row provider result; absent means silent non-query.", and schema "Names must be nonblank and unique with ordinal case-insensitive comparison." Verify empty first-result selection, ordinal native/null/binary row values, incremental delivery/partial failure, downstream truncation, reader-then-command disposal and safe primary/cleanup error retention; record results in `specs/007-export-generic-sql-query/quickstart.md`.
- [X] T047 [US2] Run history/nested-cleanup and independent archiving execution checks in `Fast1data.SqlServer/tests/Migration.Tests.ps1`, `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` and `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`; preserve `Fast1data.SqlServer/private/migration/Get-Executed.ps1` exact SELECT/filter, open delegated connection and NVarChar/Size 32 descriptor with -WhatIf:$false -Confirm:$false. Enforce phase "Bound filter, not an output property.", script_name "Preserve exact stored spelling/case/separators.", checksum "Return unchanged after script_name.", and reader-command-connection cleanup order; keep phase nvarchar(32), schema and execution semantics unchanged and record outcomes in `specs/007-export-generic-sql-query/quickstart.md`.
- [X] T048 [US2] Reconcile the hardcoded total in `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` only with actually discovered cases added to its included suites (baseline 249), retaining unexpected-skip rejection and the approved Windows-only filesystem skip; run `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and all five loading patterns × six operation orders in `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`. Record fresh-process manifest/direct/model imports, exact selected-root provenance, unchanged metadata and all 16 owners in `specs/007-export-generic-sql-query/quickstart.md`.
- [X] T049 [US2] Run the full ten-suite source command from section 2 of `specs/007-export-generic-sql-query/quickstart.md`, including `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` and all migration phase/command/execution/preflight suites; compare failures to T035, resolve amendment regressions, and record actual counts/skips and remaining baseline failures separately. Do not treat the historical six-case failure record as a successful current run.
- [X] T050 [US2] Run `Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` and section 3's public SQL smoke from `specs/007-export-generic-sql-query/quickstart.md` against the explicitly configured test SQL environment when available; retain existing uniquely named disposable fixtures and guarded teardown. Verify real result/schema/null/binary/StoredProcedure behavior, early-stop connection reuse, exact persisted history keys/collation, force/retry/preview and cleanup, recording actual results or unavailable SQL as unverified without exposing credentials.

**Checkpoint**: Source compatibility is measured against the baseline; source success alone does not complete packaged/native acceptance.

---

## Amendment Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Finish consistent guidance, changed-file analysis and separate package/native evidence.

- [X] T051 Update affected source-location/loader guidance in `README.md` and any affected references in `Fast1Migration.md` to identify the canonical public query files and independently loaded model scope; retain runnable six-command examples, connection ownership, idempotent migration guidance and existing dependency/runtime/release versions. Correct only superseded location guidance; do not rewrite historical evidence.
- [X] T052 Run Invoke-ScriptAnalyzer on every new/modified .ps1/.psm1/.psd1, including `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQuery.ps1`, `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQueryReader.ps1`, `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`, root/model modules and affected tests/fixtures; recheck project settings, use them if present, enforce tab-indented multiline blocks and resolve new warnings/errors without suppression. Record covered paths/results or analyzer unavailability in `specs/007-export-generic-sql-query/quickstart.md`; rerun for any later PowerShell edit.
- [X] T053 Run `out/publish.ps1 -StageOnly` after source regressions and changed-file analysis, inspect package-wide analyzer output and exit status, and verify all three canonical public files/help plus existing RID assets are copied into `out/Fast1data.SqlServer/`; preserve packaging behavior and runtime/dependency versions, and record staging evidence separately in `specs/007-export-generic-sql-query/quickstart.md`. Carry unrelated baseline failures forward explicitly; amendment-caused failures must be fixed before accepting staging.
- [X] T054 Run section B's six staged affected suites from `specs/007-export-generic-sql-query/quickstart.md` against `out/Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1`, `out/Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1`, `out/Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, `out/Fast1data.SqlServer/tests/Migration.Tests.ps1`, `out/Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and `out/Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`; repeat fresh-process manifest/direct/model-first imports and complete Get-Help checks for the three new commands, requiring exact staged public provenance, six exports, unchanged metadata and empty nested exports. Record staged counts/failures/skips independently; StageOnly does not run these checks.
- [X] T055 Verify source/staged fresh imports and available SQL smoke on supported native win-x64, linux-x64 and osx-x64 hosts using sections 1/3 and amendment A-C of `specs/007-export-generic-sql-query/quickstart.md`; record host/runtime, selected distribution and actual outcomes separately, labeling unavailable hosts and live environments unverified. Bundled-file/hash inspection alone is not native execution.
- [X] T056 Complete an amendment acceptance section in `specs/007-export-generic-sql-query/quickstart.md` against FR-001 through FR-006, SC-001 through SC-003 and all three files in `specs/007-export-generic-sql-query/contracts/`; keep preceding evidence intact, distinguish source/staged/live/native results, record remaining failures and unavailable environments, and update relocation status in `specs/007-export-generic-sql-query/spec.md` only to the extent established by those checks. Material unresolved ownership or migration-integrity failures block release; an overall red suite or unrun acceptance must not be reported as a passing release.

---

## Dependencies & Execution Order

### Phase Dependencies

The checked T001-T034 are historical prerequisites, not work to rerun. Current execution is:

```text
Setup T035-T036
    |
    v
Foundation T037
    |
    v
US1 (P1): T038 -> T039 -> T040 [layout MVP]
    |
    v
US2 (P1): T041 + T042 [parallel test authoring]
    |
    v
T043 -> T044 -> T045 -> T046 -> T047 -> T048 -> T049 -> T050
    |
    v
Polish T051 -> analyzer T052 -> stage T053 -> staged T054
    |
    v
Native acceptance T055 -> evidence/status T056
```

- Setup captures the unchanged implementation and acceptance map; foundation prepares observations before either story.
- US1 depends on foundation. T038 must fail for absent public files before T039; run only focused layout acceptance at T040, since model integration remains in US2.
- US2 implementation depends on US1's canonical files. T041/T042 can be authored together after T040 and must expose absent model dependencies/provenance before T043/T044.
- T043/T044 finish both consumer loading paths before behavior checks. Tests must retain all six metadata entries rather than regenerate a snapshot to conceal changes.
- T045-T050 are acceptance runs of existing behavior, with additions only for demonstrated gaps. They reuse test files and the evidence record, so these execution tasks are intentionally serialized. Any production fix requires rerunning affected checks.
- T048 observes final child inventories before the full source run. A new ModuleLoaders case does not automatically increase the shared worker inventory; count only cases in included suites.
- T050 may record unavailable SQL without inventing a pass. T055 likewise records unavailable native hosts; neither limitation silently satisfies release acceptance.
- T052 analyzes every changed PowerShell file before staging; subsequent edits require affected tests, renewed analysis and restaging before T054/T055 results are accepted.
- Polish follows source story verification. US2's full independent acceptance includes the staged checks; T056 reconciles actual evidence without erasing earlier limitations.

### Parallel Opportunities

- **US1**: Its own test/move/check tasks are sequential because they share files and each consumes the previous result. After foundation, T038's layout-test authoring can run alongside US2 T042's independent provenance-fixture authoring; execution of T042's acceptance still waits for US1 and T044. This early authoring option adds no story implementation dependency.
- **US2**: T041 and T042 are marked [P] because their edited files are disjoint after foundation. Their tests run before consumer implementation.
- Root/model loader changes are sequenced for a reviewable compatibility checkpoint; do not run tests against partially edited distributions.
- Test suites that import the same modules, child matrices and writes to quickstart.md are serialized. Live SQL and staging/native work follow their prerequisites.
- No new parallel-agent execution is requested by this task list; these examples describe implementation scheduling.

---

## Parallel Example: User Story 1

After T037, optional cross-story test authoring uses different files:

```text
US1 T038: AST layout cases in Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1
US2 T042: Exact query provenance in Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1
           and Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1
```

T039 waits for the expected T038 failures; T040 follows relocation. T042's runtime acceptance remains pending until T044. There is no safe parallel pair within US1 itself.

## Parallel Example: User Story 2

After T040, or after finishing any early T042 authoring:

```text
T041: Inventory, literal loading and 12 public dependency fault cases
      in Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1
T042: Provenance, defining session-state and owner checks
      in Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1
      and Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1
```

Run the added cases for expected failures before T043/T044, then retain all existing export, assembly, ownership and unexpected-skip assertions.

---

## Implementation Strategy

### MVP First (User Story 1)

1. Complete T035-T037 against the existing implementation; reuse infrastructure and completed behavior.
2. Write the layout acceptance tests, relocate both definitions/help intact and validate the canonical paths through T040.
3. Review that layout increment as the MVP. Complete US2 before claiming working source/package compatibility or releasing it.

### Incremental Delivery

1. Preserve T001-T034 as historical evidence; never follow their superseded shared-definition/export instructions.
2. Deliver current US1's exact matching public files and zero duplicate definitions.
3. Deliver current US2's root/model loading and strict source provenance, then rerun existing parameter/query/cleanup/history/archiving/import behavior.
4. Update guidance, analyze changed PowerShell, stage, and independently validate packaged and available native/live behavior.
5. Record each actual outcome separately and leave unmet checks visible. Do not reopen unrelated baseline failures or broaden scope without evidence that relocation introduced a regression.

## Validation and Coverage Map

| Requirement | Current tasks |
| --- | --- |
| FR-001 / SC-001: matching public files, definitions and help | T038-T040, T054 |
| FR-002: private-only support, one canonical public definition | T038-T039, T041-T042 |
| FR-003 / SC-002: six exports for source/staged manifest/direct imports | T041-T044, T048-T049, T053-T055 |
| FR-004: unchanged API/help/defaults/values/errors/ownership | T039, T042, T045-T046, T050, T054 |
| FR-005: history and independent archiving resolution | T041-T042, T044, T047-T050, T054 |
| FR-006 / SC-003: documentation and complete regression evidence | T035-T036, T048-T056 |
| Constitution IV/V and analyzer workflow | T035, T048-T056 |

**Generation summary (before implementation)**: 56 tasks total: 34 completed historical tasks and 22 pending amendment tasks. Pending story tasks: US1 = 3 (T038-T040), US2 = 10 (T041-T050). Pending shared work = 9 (setup 2, foundation 1, polish 6). Two tasks carry [P]; US1 additionally has the explicitly bounded cross-story test-authoring opportunity above. No implementation or runtime acceptance is claimed by generation.


**Execution summary (2026-11-20)**: All 56 tasks are marked [X], including T035–T056 for relocation. Available Windows source/staged offline checks and analyzer/package validation are complete. Current Windows SQL acceptance and the audit reruns passed; native Linux/macOS checks remain unverified as recorded in quickstart.md. The full source/staged results and resolved audit setup failures are retained there; this is not a full cross-platform release approval.
