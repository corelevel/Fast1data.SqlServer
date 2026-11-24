---
description: "Executable tasks for per-table archiving bulk-copy timeouts"
---

# Tasks: Per-Table Bulk Copy Timeout

**Input**: Design documents from `specs/009-add-bulk-copy-timeout/`.

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contract](contracts/bulk-copy-timeout.md), [quickstart.md](quickstart.md), and `.specify/memory/constitution.md` version 2.0.0.

**Tests**: Explicitly required by FR-010/011 and the acceptance scenarios. Extend existing Pester suites with controlled actual-method tests and live SQL Server tests. Write new assertions before their production changes and establish relevant failures where the environment permits. Documentation acceptance uses review and a live preparation rehearsal. Record unavailable checks as unrun.

**Organization**: Four story phases follow the specification's priority order (US1, US2, US3: P1; US4: P2). Shared storage is foundational because every story uses it. Generating this file does not implement the feature or run its acceptance checks. Remain on the existing `dev` branch.

## Format: `[ID] [P?] [Story] Description`

- `[P]` permits concurrent work only after stated prerequisites and only in different files.
- `[US1]` through `[US4]` identify the corresponding specification stories.
- Tasks without story labels belong to setup, foundation, or cross-cutting verification.
- Use tab-indented multiline PowerShell control-flow blocks, with opening braces on the statement line. Preserve `.vscode/` tracking.

## Path Conventions

- Schema: `Fast1data.SqlServer/schema/archiving/tables.sql` and `Fast1data.SqlServer/schema/archiving/sprocs.sql`.
- Runtime: `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`.
- Coverage: existing `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` and `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`; keep helpers test-local.
- Operator documentation: `Fast1Archiving.md` and `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1` comment help.
- Evidence: create `specs/009-add-bulk-copy-timeout/validation.md` during implementation. Record commands, runtime/provider/server versions, suite counts, observed values/timings, failure/retry state, cleanup, and unavailable checks without secrets.
- All paths are relative to the repository root.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Identify runnable verification environments without adding dependencies.

- [X] T001 Verify PowerShell 7.6+ Core on supported x64 Windows/Linux, existing SqlClient 7.1.2/ScriptDom bundles, Pester, PSScriptAnalyzer and repository analyzer settings using `specs/009-add-bulk-copy-timeout/quickstart.md`; create `specs/009-add-bulk-copy-timeout/validation.md` with prerequisite availability and all checks initially unrun. Identify an explicitly selected disposable SQL instance through `FAST1_TEST_ARCHIVING_SQL_CONN_STR` without printing its value; record create/drop database and fixture permissions plus SQL Server 2022+/compatibility 160 requirements for existing `generate_series` cases. If bundles are absent, use `build/build.ps1` and its existing .NET 10 prerequisites without upgrading dependencies.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the preserved baseline and shared storage contract before story execution.

- [X] T002 Record the pre-change command, configuration, and recovery baseline in `specs/009-add-bulk-copy-timeout/validation.md`: inspect `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, `Fast1data.SqlServer/schema/archiving/tables.sql`, `Fast1data.SqlServer/schema/archiving/sprocs.sql`, `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1`, and `Fast1data.SqlServer/Fast1data.SqlServer.psd1`; run existing `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1`, and `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` when prerequisites exist. Capture ordinary command properties under a distinct connection `Command Timeout` such as 2 seconds, unchanged public signature/exports, create-only setup, copy options, batching, streaming and checkpoint behavior. Keep live integration files out of offline runs by filename because tag exclusion still executes their global setup.
- [X] T003 Add fresh-schema contract assertions in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` for SQL `int NOT NULL`, default constraint `DF_SourceTable__BulkCopyTimeout` with expression `30`, and enabled/trusted check `CK_SourceTable__BulkCopyTimeout` with expression `BulkCopyTimeout >= 0`; use the existing GO-aware deployment helper and isolated disposable databases. Establish the missing-column failure before T004 where live SQL is available; value-specific acceptance belongs to US2/US4.
- [X] T004 Extend only the existing create-if-absent `dbo.SourceTable` definition in `Fast1data.SqlServer/schema/archiving/tables.sql` with `BulkCopyTimeout`, enforcing the data-model constraints verbatim: "`int NOT NULL`", "Named default: `DF_SourceTable__BulkCopyTimeout`, expression `30`.", "Named check: `CK_SourceTable__BulkCopyTimeout`, expression `BulkCopyTimeout >= 0`.", "Valid persisted range: 0 through 2,147,483,647 inclusive.", and "Omitted insert field receives 30. Explicit null is rejected by `NOT NULL`." Keep the column/default/check inside the current creation guard; add no existing-table alteration branch, migration file or automatic repair. Dependencies: T003.

**Checkpoint**: Shared schema is defined; baseline and environment limits are recorded. US1 runtime work can begin. Live schema assertions remain an open gate if SQL is unavailable.

## Phase 3: User Story 1 - Set a time limit for each source table (Priority: P1) - MVP

**Goal**: Carry each table's positive timeout from storage through metadata to every copy object before writing, preserving query limits and failure/retry behavior.

**Independent Test**: Load two tables in one group with 60 and 120 seconds; execute each actual source-key, destination-key and archive-data copy method and observe its owning table's timeout at write entry. Confirm a short real positive bulk timeout surfaces failure without false completion, then succeeds through existing retry behavior. Ordinary commands retain their baseline timeout.

### Tests for User Story 1

- [X] T005 [P] [US1] Extend metadata DataTable rows and table fixtures in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` to include the required `BulkCopyTimeout` result field. Add assertions that `TableGroup.ReadSourceTables()` produces real typed `Table` objects with unchanged positive values, including two tables at 60/120 in the same group and reversed traversal order. Add a missing-result-column case proving the normal read fails rather than silently using a fallback value. Establish relevant failures before T009.
- [X] T006 [US1] Extend the harness in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` to execute actual `BulkCopySourcePK()`, `BulkCopyDestinationPK()` and `BulkCopyTable()` methods; existing `RealCopy` reaches only archive-data copying. Inspect the timeout at entry to overridden `WriteToServer`, with multiple reconciliation pages and archive batches, and verify owning-table isolation, unchanged options/mappings/streaming/batch sizes, skipped/no-row behavior and ordinary command properties. Inject write/interruption and cleanup failures at each copy boundary; retain primary errors, independent resource release and absence of subsequent success checkpoints. Establish relevant failures before T010. Dependencies: T005.
- [X] T007 [P] [US1] Add live positive metadata and write-boundary cases in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`: load 60/120 for two tables in one group through the real procedure/model, preserve active/group filtering, observe all three copy properties immediately before forwarding to the real provider write, and verify archived keys and normal completion. Add an ordinary-command regression with connection `Command Timeout=2` and a longer `WAITFOR` query, comparing properties/failure with T002 without changing production query helpers. Verify the actual loaded module scope before installing mocks.
- [X] T008 [US1] Add a bounded positive-timeout/retry scenario and test-local coordination helpers in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`: prepare source readers, isolate blocking to an actual copy write target with an independent connection, confirm write entry, and hold the barrier beyond a short bulk limit such as 2 seconds while command limits exceed the timing window. Assert the provider bulk-timeout failure within a broad deadline, inspect durable effects/working keys/`ProcessState` for no premature success, release the barrier, and retry with a fresh invocation to eventual correct completion. Use a separate watchdog and unconditional lock/worker/resource cleanup; do not imply earlier batches rolled back or test only a delayed query. Dependencies: T007.

### Implementation for User Story 1

- [X] T009 [US1] Add the named `BulkCopyTimeout` result field to `dbo.stp_GetSourceTable` in `Fast1data.SqlServer/schema/archiving/sprocs.sql` without changing its parameter, existing fields or group/active filtering. Map `$sqlReader.GetInt32($sqlReader.GetOrdinal('BulkCopyTimeout'))` in `TableGroup.ReadSourceTables()` and add `[int]$BulkCopyTimeout` without an initializer beside batch-size properties in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`. Enforce "No conversion to milliseconds or a smaller integer type; preserve the stored value." SQL configuration owns the default; private direct construction must explicitly supply a timeout before copying. Do not catch missing metadata or add old-schema fallback. Dependencies: T005-T008 test definitions.
- [X] T010 [US1] Assign `$bulkCopy.BulkCopyTimeout = $this.BulkCopyTimeout` unconditionally before each `WriteToServer` in `BulkCopySourcePK()`, `BulkCopyDestinationPK()` and `BulkCopyTable()` in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, including each new reconciliation-page/archive-batch object. Preserve `Get-ArchivingBulkCopy`'s signature, command timeout behavior, copy options, mappings, streaming, batching, resource ownership, processing order, checkpoints and retry policy; add no public option or new abstraction. Dependencies: T009.
- [X] T011 [US1] Run `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` after T009-T010 and record observed stage/table/timeout values, traversal/page/batch coverage, primary-error/cleanup results, skipped stages and command-timeout comparisons in `specs/009-add-bulk-copy-timeout/validation.md`. Resolve failures attributable to the feature without weakening existing recovery assertions.
- [X] T012 [US1] Run the fresh-schema, positive propagation, ordinary-query and real bulk-timeout/retry cases in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` on the selected disposable instance; record actual versions, timings, failure source, persisted state, retry results and cleanup in `specs/009-add-bulk-copy-timeout/validation.md`. Mark unavailable scenarios unrun. Dependencies: T010-T011.

**Checkpoint**: Positive limits work through all stages with failure/query isolation evidence. This is the first implementation increment; default/zero, upgrade and invalid-value acceptance still gate delivery.

## Phase 4: User Story 2 - Keep the default or explicitly wait without a limit (Priority: P1)

**Goal**: Preserve the existing 30-second default and pass explicit zero unchanged as unlimited bulk waiting.

**Independent Test**: Omit the field on a fresh configuration insert and confirm stored/model/write values of 30. Repeat all three actual methods with zero; a real copy must complete after a write barrier held beyond 30 seconds, while ordinary query limits remain effective.

### Tests and Integration for User Story 2

- [X] T013 [P] [US2] Extend `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` using T005-T006 with metadata-to-model and all-three-write cases for 30, zero and 2147483647, repeated reconciliation pages/archive batches, and configured timeout loading for empty readers. Assert explicit zero at write entry, never truthiness fallback, and repeat baseline ordinary command-property assertions for bulk values 30/120/zero. Do not wait for the Int32 maximum to elapse. Dependencies: US1.
- [X] T014 [P] [US2] Add fresh-installation cases in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` that omit the column on a valid insert and read 30 from storage, procedure and model; observe default and explicit zero at all three real provider write boundaries and verify correct destination data/completion. Enforce "Omitted insert field receives 30. Explicit null is rejected by `NOT NULL`." and "No conversion to milliseconds or a smaller integer type; preserve the stored value." Reuse T007 observations rather than replacing real writes with mocks. Dependencies: US1.
- [X] T015 [US2] Extend the bounded live fixture in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` with bulk timeout zero: hold the isolated write barrier beyond 30 seconds, such as 35 seconds, release it and verify that copy completes. Use an independent maximum duration such as 90 seconds, cancellation and unconditional blocker/resource cleanup, with query limits high enough to isolate bulk waiting. Separately repeat the low connection `Command Timeout` delayed-query regression with zero bulk timeout and confirm the prior query limit still applies. Dependencies: T014 and T008.
- [X] T016 [US2] Run the expanded controlled and live cases in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` and `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`; record default/zero/Int32 propagation, real elapsed wait/completion, query independence, watchdog and cleanup results in `specs/009-add-bulk-copy-timeout/validation.md`. Fix any feature defects in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` using unconditional value preservation, without changing query timeouts. Dependencies: T013-T015.

**Checkpoint**: Defaulted configurations retain 30 and zero survives all boundaries; live evidence distinguishes unlimited bulk waiting from ordinary query limits.

## Phase 5: User Story 3 - Prepare an existing installation before upgrading (Priority: P1)

**Goal**: Give operators a complete manual preparation sequence that preserves existing configuration and progress with 30 seconds for every old row.

**Independent Test**: Follow the guide alone on a disposable legacy installation containing multiple configuration rows and retained progress/working sets. A setup rerun must leave it unchanged; manual storage preparation followed by procedure deployment must produce valid metadata and successful resumed operation.

### Implementation and Acceptance for User Story 3

- [X] T017 [P] [US3] Update `Fast1Archiving.md` with seconds, default 30, zero/unlimited and positive Int32 semantics, negative/null rejection, per-table scope, all three copy stages and independent query limits. Replace the claim that no persistence/procedure upgrade is needed. Provide the manual order: stop runs, select the configuration database, add the required column, populate every preexisting row with 30, establish/validate non-null/default/nonnegative constraints, deploy `dbo.stp_GetSourceTable`, verify metadata and resume one process per group. Explicitly state setup is create-only and reruns cannot add the field; retain identities, relationships, progress and working sets, with no shipped migration or automatic alteration facility. Dependencies: foundation; documentation may overlap US1/US2.
- [X] T018 [P] [US3] Update comment help in `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1` to explain database-configured `BulkCopyTimeout`, seconds/default/zero, three affected copy operations, unchanged query limits and mandatory storage preparation followed by metadata-procedure deployment before using the changed module. Link the complete guide and preserve the command signature, explicit export and output/error contract. Dependencies: foundation; may run alongside T017.
- [X] T019 [US3] Add a disposable legacy-schema rehearsal in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` with at least two preexisting configuration rows plus progress/working-set sentinels. Run updated `tables.sql` through the GO-aware helper and prove the missing column stays absent and rows/state stay unchanged. Then follow T017's manual sequence within test-local setup, confirm every old row is 30, future omitted inserts default to 30, constraints and metadata are prepared, and the changed module resumes using preserved identities/relationships/state. Include a missing-column/old-projection failure check without asserting a fragile exact error message or adding compatibility repair. Dependencies: T017-T018 and US1/US2; serialize with other edits to this integration file.
- [X] T020 [US3] Run the legacy preparation/recovery rehearsal in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` and review `Fast1Archiving.md` as a standalone operator runbook; record create-only rerun observations, before/after configuration and progress evidence, preparation order, validation and cleanup in `specs/009-add-bulk-copy-timeout/validation.md`. Keep manual alterations confined to disposable fixtures/operator instructions; do not create a migration artifact. Dependencies: T019.

**Checkpoint**: Existing installations have verified manual guidance; setup still performs no automatic change to existing tables or rows.

## Phase 6: User Story 4 - Reject invalid timeout configuration (Priority: P2)

**Goal**: Enforce database-boundary rejection of negative and explicit-null values while preserving valid settings.

**Independent Test**: Attempt inserts and updates with -1, Int32 minimum and SQL null; assert the expected constraint/nullability errors and unchanged prior values. Insert/update zero, 1, 120 and Int32 maximum and read each back unchanged.

### Tests and Acceptance for User Story 4

- [X] T021 [P] [US4] Add parameterized negative/null insert and update cases in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` for -1, -2147483648 and explicit SQL `NULL`. Supply valid unrelated required fields, isolate rejected writes, assert the check-constraint or nullability failure rather than an incidental error, and verify the prior valid setting survives rejected updates. Enforce "Negative inserts and updates fail. Failed updates preserve the prior valid value." and "Omitted insert field receives 30. Explicit null is rejected by `NOT NULL`." Dependencies: US1/US2; may overlap T017-T018 documentation, but never another integration-file edit.
- [X] T022 [US4] Add accepted insert/update boundary cases to `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` for 0, 1, 120 and 2147483647, verifying storage/procedure/typed-model round trips and trusted named constraints on fresh and manually prepared schemas. Enforce "Valid persisted range: 0 through 2,147,483,647 inclusive." and "No conversion to milliseconds or a smaller integer type; preserve the stored value." Reuse US2's write-boundary maximum/zero coverage; do not add production validation or fallback beyond the planned SQL constraints. Dependencies: T021 and T019.
- [X] T023 [US4] Run the accepted/rejected value matrix in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`, resolving schema defects only within the create-only definition in `Fast1data.SqlServer/schema/archiving/tables.sql` and corresponding test-local preparation. Record actual errors, preserved prior values, round trips and cleanup in `specs/009-add-bulk-copy-timeout/validation.md`. Dependencies: T022.

**Checkpoint**: Valid boundaries round-trip, invalid saves fail at the intended database boundary, and failed updates preserve valid configuration.

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile contracts, finish regression evidence and satisfy explicit release governance.

- [X] T024 Run the complete affected suites from `specs/009-add-bulk-copy-timeout/quickstart.md`: `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, `Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1`, `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1`, and `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`. Run `Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1` with its separate explicitly configured test variable against the selected disposable instance. Retain partial-key recapture, destination reconciliation, checkpoint failure, committed-copy retry, purge and cleanup regressions; record actual pass/fail/skip/unrun outcomes in `specs/009-add-bulk-copy-timeout/validation.md`. Dependencies: US1-US4.
- [X] T025 Review `Fast1Archiving.md`, `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1`, `Fast1data.SqlServer/schema/archiving/tables.sql`, `Fast1data.SqlServer/schema/archiving/sprocs.sql` and `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` against `specs/009-add-bulk-copy-timeout/contracts/bulk-copy-timeout.md` and FR-001-FR-011. Record consistency evidence in `specs/009-add-bulk-copy-timeout/validation.md`: no new public parameter/export, dependency upgrade, query-timeout assignment, factory interface, migration/repair path, retry policy, progress format or working-set/order change. Dependencies: US1-US4.
- [X] T026 Record the explicit maintainer release-version decision for this configuration compatibility change in `specs/009-add-bulk-copy-timeout/validation.md`, referencing the current version in `Fast1data.SqlServer/Fast1data.SqlServer.psd1` (0.2.1 during planning). Obtain the decision if none has been supplied; leave release pending until it exists, without inventing approval or blocking unrelated implementation/verification. Dependencies: T025.
- [X] T027 Apply the selected release version and matching compatibility release notes in `Fast1data.SqlServer/Fast1data.SqlServer.psd1`, describing per-table timeout semantics and mandatory manual storage/procedure preparation. Preserve PowerShell 7.6+ Core, supported platforms, dependencies and explicit exports; record metadata consistency in `specs/009-add-bulk-copy-timeout/validation.md`. Do not publish a release. Dependencies: T026.
- [X] T028 Run `Invoke-ScriptAnalyzer` on every modified `.ps1`, `.psm1` and `.psd1`, including `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1`, both modified archiving test suites and `Fast1data.SqlServer/Fast1data.SqlServer.psd1`, using repository settings if present. Resolve new findings and enforce tab-indented multiline blocks without suppressing rules; record unrelated baseline findings or unavailable analysis in `specs/009-add-bulk-copy-timeout/validation.md`. Dependencies: all PowerShell edits, including T027.
- [X] T029 Finalize `specs/009-add-bulk-copy-timeout/validation.md` against SC-001-SC-006 and `specs/009-add-bulk-copy-timeout/quickstart.md`, linking evidence for every story, all three write boundaries, real timeout/zero waiting, query independence, manual preparation and recovery. Confirm cleanup and record remaining environment gaps or material integrity risks as open release gates. Mark tasks complete only for work actually performed; release remains pending without required SQL evidence, resolved integrity risks, analyzer results and the recorded version decision. Dependencies: T024-T028.

## Dependencies & Execution Order

### Phase Dependencies

```text
T001 Setup -> T002 Baseline -> T003 Schema assertions -> T004 Shared schema
                                                         |
                                                         +-> US1 (T005-T012) -> US2 (T013-T016)
                                                         |                          |
                                                         +-> US3 docs (T017/T018) ---+-> US3 rehearsal (T019/T020)
                                                                                    |
                                      US1 + US2 -> US4 rejection (T021) --------------+-> US4 boundaries/run (T022/T023)

US1 + US2 + US3 + US4 -> T024/T025 -> T026 -> T027 -> T028 -> T029
```

- US1 owns the common metadata/model/write implementation and is the first complete runtime increment.
- US2 depends on that path and adds independent default/unlimited acceptance; it does not need a separate production timeout mechanism.
- US3 documentation can begin after foundation. Its live rehearsal depends on the implemented path and finished runbook. US3 does not depend on US4; its own prerequisite checks can verify the shared constraints before the full US4 matrix.
- US4's negative/null tests can follow US1/US2 independently of documentation, but its prepared-schema boundary matrix reuses US3's fixture.
- Live tests require the explicitly selected disposable instance. Unavailable environments do not prevent independent source/docs work, and their tests remain unrun.
- T024 and T025 can be carried out independently after stories; serialize their writes to `validation.md`. T026/T027 gate release metadata only. Complete unaffected checks even if the release decision is pending; rerun analysis for any later manifest edit.

### Within Each Story

- Add tests and establish the relevant pre-change failure where feasible before changing production behavior.
- Metadata projection/model mapping precedes copy propagation. Copy propagation precedes execution acceptance.
- Complete both controlled evidence and necessary live SQL evidence; property interception cannot prove real waiting or constraints.
- Serialize edits to the same existing test/runtime file. `[P]` does not authorize concurrent writes to shared evidence.

### Parallel Opportunities and Examples

**US1**: After foundation, T005 (controlled metadata tests in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`) and T007 (live positive/query tests in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`) can proceed concurrently. T006 follows T005; T008 follows T007. Integrate test definitions before T009/T010.

**US2**: After US1, T013 (controlled default/zero/maximum cases) and T014 (live default/zero cases) can proceed concurrently in the two different suites. T015 follows the integration-file work; T016 consumes both.

**US3**: After foundation, T017 (`Fast1Archiving.md`) and T018 (`Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1` help) can proceed concurrently, also alongside runtime work in other files. Finish both before the standalone-guide rehearsal in T019/T020.

**US4**: T021 edits the integration suite and may overlap unfinished US3 documentation T017/T018 after US1/US2. T021/T022 themselves are sequential because they share `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`; there is no independent within-story file split worth introducing.

These are scheduling examples, not instructions to spawn agents or run competing timing/database cases concurrently.

## Implementation Strategy

### MVP First

1. Complete setup and foundation, then US1's metadata, runtime and positive-limit acceptance.
2. Validate every real copy boundary, table isolation, query limits and timeout recovery as the first demonstrable increment.
3. Treat US1 as the suggested MVP scope, with manual preparation still required for any existing installation. Final delivery requires all requested default/zero, upgrade and validation behavior plus the final gates.

### Incremental Delivery

1. US1 establishes the reusable timeout path with positive settings.
2. US2 proves omitted defaults, explicit zero and real unlimited waiting without relaxing query limits.
3. US3 delivers the complete manual upgrade runbook and rehearses retained-state operation.
4. US4 completes invalid-value and accepted-boundary evidence across fresh/prepared schemas.
5. Finish contract review, affected regressions, release-version metadata, analysis and recorded evidence before release readiness is claimed.

## Notes

- Shared schema, metadata and runtime work is listed once; later stories reuse it and focus on their independent acceptance scenarios.
- The database supplies the default of 30; the typed property has no initializer and always loads the stored value during normal execution. Private direct construction must explicitly supply a timeout before copying. Zero is always assigned explicitly. Missing normal metadata is an installation prerequisite failure.
- No migration script, automatic existing-table alteration, new public option or transparent legacy fallback is part of this feature.
- Live timing fixtures must terminate through their own watchdog and cleanup even when assertions fail. Unlimited bulk waiting does not imply an unlimited test run.
- Release-version selection is an explicit governance task, not an unresolved technical design choice or authorization to publish.
