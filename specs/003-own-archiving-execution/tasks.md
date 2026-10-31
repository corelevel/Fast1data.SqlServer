# Tasks: Own Archiving Execution

**Input**: Design documents from `specs/003-own-archiving-execution/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/archiving-execution.md`, `quickstart.md`, and `.specify/memory/constitution.md`.

**Tests**: Required by FR-012–013 and the constitution. Retain existing copy/delete interruption fixtures and add controlled ownership/error tests plus real SQL Server durability/constraint tests. Write story tests before the corresponding implementation and establish the expected failing behavior. Mocks establish attempts and sequencing; independent SQL observers establish durability.

**Organization**: Setup → shared execution foundation → US1 (P1) → US2 (P1) → US3 (P2) → cross-cutting validation and guidance. Existing execution ownership is a shared prerequisite; each story completes and verifies its own behavior.

## Format: `[ID] [P?] [Story] Description`

- Every task uses an unchecked checkbox, sequential task ID, optional `[P]`, and a story label only inside a story phase.
- `[P]` identifies work that can overlap a named task in a different file after shared prerequisites. It does not waive dependencies or permit concurrent edits to the same file.
- Paths are relative to the repository root, `C:/Dev/Fast1data.SqlServer`.

## Path Conventions

- Production execution: `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` and `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1`.
- Controlled tests: new `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`; real SQL tests: existing `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`.
- Preserve the current audit/migration test-file names and unrelated in-progress edits. No new production dependencies, persistence formats, procedure signatures, public parameters, or exports are planned.
- All changed PowerShell must use tab-indented multiline control-flow blocks per `AGENTS.md` and pass the constitution's analyzer requirements.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Make both validation paths safe to invoke before changing execution.

- [X] T001 Parameterize `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` with Pester container inputs `ConfigConnectionString`, `SourceConnectionString`, and `DestinationConnectionString`; remove fixed targets/credentials and all fallback connections, reject missing inputs, empty database names or configured-target mismatches before any mutation, require configuration/source on the same instance, use unique registered fixture identities, deploy `Fast1data.SqlServer/schema/archiving/tables.sql` before `Fast1data.SqlServer/schema/archiving/sprocs.sql` only in the selected configuration database, and remove only registered fixtures/injections during teardown. Preserve existing interruption and destination-schema fixtures.
- [X] T002 [P] Create the SQL-independent request harness in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, loading the same private `Invoke-ArchivingProcess` interface and supporting narrow private resource/SQL substitutions and ordered event recording; verify this suite performs no SQL setup or real connection opens, and use fresh `pwsh` processes when class reload would otherwise reuse stale definitions. Do not introduce public injection parameters or a resource framework.

**Checkpoint**: Controlled tests require no SQL; integration setup refuses unspecified or mismatched targets. T001 and T002 may run concurrently.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish one protected execution lifetime and shared failure handling before hardening individual stories.

- [X] T003 Implement scoped internal failure collection in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`: preserve the original operation ErrorRecord, promote the first cleanup-only failure, merge nested failures in encounter order, and expose entries at `Exception.Data['Fast1Archiving.CleanupFailures']` with `Action`, `GroupName`, optional `SourceTable`/`ProcessStateId`, `ResourceRole` or source constraint identity, `ErrorType`, and sanitized `Message`. Preserve the data-model rules "Original operation ErrorRecord, or first cleanup-only error, plus ordered cleanup contexts." and "No connection strings, credentials or sensitive SQL; no persisted failure schema/new public success object."
- [X] T004 Correct the resource lifetime in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1` so command creation, command configuration, parameter validation/setup, execution, and disposal are protected; keep its signature, scalar/non-query behavior and GenericSqlParam mapping compatible, preserve the primary error on disposal failure, and make nested cleanup context available to execution without adding a dependency on archiving classes.
- [X] T005 Make `TableGroup` construction inert in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, including removing connection allocation from field initializers; add single-use `Execute()` with protection established before allocation, register each allocated handle before Open, and move configuration/table initialization under that lifetime. Preserve "Created → initializing → preparation/archive → purge → releasing → succeeded/failed; no-work exits also release." and "Every allocated connection/reader/command/bulk-copy handle registered before use." Provide only the narrow private seams required by T002.
- [X] T006 Apply guarded, independent cleanup to model metadata/state readers, SQL commands, bulk-copy objects and group connections in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, including no-row returns and failed initialization; replace sequential disposal that stops at the first error, collect failures through T003, and release short-lived readers before checkpoint connection reuse. Preserve "Dependencies require short-lived readers/bulk-copy before connection release and restoration before releasing its connections." and "Failed release cannot prevent independent attempts."
- [X] T007 Route `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1` through inert group construction and one `Execute()` request; move its existing preparation/archive/purge orchestration into owned group/table operations in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`. Preserve both command signatures and existing traversal while removing caller state mutations, checkpoint writes, FK toggles and disposal ordering. Protect any remaining outcome handling so it cannot mask an execution error. Subsequent story tasks harden these internal operations rather than reintroducing caller sequencing.

**Checkpoint**: Every acceptance test can cross the same execution request; constructor failure cannot strand resources outside its owner. Complete T003–T007 in order. All story implementation depends on this phase.

---

## Phase 3: User Story 1 — Resume from actual batch effects (Priority: P1) — MVP

**Goal**: Confirm progress only after effects and successful writes; recover using retained captured keys and independently committed SQL truth.

**Independent Test**: In explicitly selected disposable SQL databases, fail copying, deleting and each post-effect checkpoint, inspect rows/state/working tables through fresh connections, remove the fault and rerun the same request. Final destination keys are unique and complete, no unfinished selected key is skipped, and purge never deletes outside the captured set. Include transition failure and changed-eligibility recovery.

### Tests for User Story 1

- [X] T008 [P] [US1] Add controlled effect/checkpoint ordering tests in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`: reset batch activity for every attempt, distinguish callback activity from successful copy, release readers before checkpoint reuse, reject advancement after an effect/write failure, stop after unconfirmed phase transitions, and reload persisted truth on a fresh execution instead of trusting rejected in-memory candidates.
- [X] T009 [P] [US1] Retain and adapt the existing failed-data-copy and failed-delete fixtures in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` to the single request; independently observe earlier committed batches, saved positions/counts, failed-range incompleteness and working-table retention before retry, then assert duplicate-free destination completion, captured-set-only deletion and existing recorded-count expectations.
- [X] T010 [US1] Add a scoped post-copy checkpoint-failure SQL fixture in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`: reject only the advancing archive checkpoint after a real committed copy, observe durable destination rows plus lagging saved state and retained working tables with independent connections, remove the injection and retry the unchanged group without editing progress. Keep this distinct from the failed-copy fixture.
- [X] T011 [US1] Add a scoped post-delete checkpoint-failure SQL fixture in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`: reject only the advancing purge checkpoint after real deletion, observe absent source keys plus lagging saved state, retry retained ranges after removing the injection, preserve outside-set keys, and assert recorded totals without reconstructing counts for already absent rows. Do not wrap effects and checkpoints in a shared fixture transaction.
- [X] T012 [US1] Add SQL failure/retry cases for partial key capture, maximum-position write, capture-date write, archive-complete write, purge-complete write, and overall-complete write in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`; assert blocked later operations/markers/table removal and recovery from persisted truth. Include a controlled committed-write/lost-response case in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, and a multi-table SQL case retaining an earlier table's completion when a later one fails.
- [X] T013 [US1] Add retained-set SQL regressions in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` combining committed copy/checkpoint failure, changed source eligibility, a copied destination row excluded by current eligibility, and newly eligible outside rows. Cover composite/nonsequential PKs, enough captured keys to exceed the `floor(2000 / PK-column-count)` parameter page bound, `AlwaysRunCheck`, and a failed partial destination snapshot followed by retry; assert original captured keys remain authoritative and no duplicate/missing archive keys or outside-set deletions result.

### Implementation for User Story 1

- [X] T014 [US1] Encapsulate `Table.State` and progress-mutating members behind owned table operations in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, retaining internal ProcessState and its existing SQL field/procedure/null mapping. Preserve the model constraints "Existing identity, relationship and timestamps.", "Maximum captured position and confirmed capture; empty confirmed set has maximum zero.", "Archive position, recorded count and phase marker.", "Purge position, recorded affected count and phase marker.", "Marker following all enabled phases and required restoration.", "Runtime loaded-incomplete flag; retain reconciliation/reset role.", and "Reset per attempt; accept after effect/checkpoint success. Callbacks alone are not durability." Persist candidate values before accepting them in memory.
- [X] T015 [US1] Implement owned process preparation/key capture in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`: load the latest incomplete process or create one, recreate/recapture only when capture is unconfirmed, write maximum before capture date, and stop on either write failure. Preserve "Existing configuration database dbo source working-table name.", "int identity used for batching; not a numeric source PK value.", "Original selected keys, including composite keys.", "Existing bit marking destination matches.", and "ProcessState.KeyCopyDate establishes completed capture." Never replace a confirmed captured set on retry.
- [X] T016 [US1] Replace destination `KeyQuery` reselection in `BulkCopyDestinationPK` in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` with bounded captured-key pages and typed, parameterized exact destination-PK predicates, including composite keys and SQL type/size/precision/scale metadata; validate/quote identifiers, cap each page at `min(KeyCopyBatchSize, floor(2000 / PK column count))`, and buffer at most one page without changing configured effect batch sizes or delays. Preserve "Existing rebuildable destination-key working table, populated from actual destination presence of captured PKs independent of current eligibility."
- [X] T017 [US1] Integrate snapshot/reconciliation ownership in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`: retain incomplete-process/AlwaysRunCheck triggers and existing purge-only preparation behavior, recreate the destination snapshot on each required attempt, close each configuration reader before snapshot writes, stream destination matches into the existing working table, and retain existing skip-flag/repaired-position procedure semantics. Stop on a partial snapshot failure and rebuild it on fresh execution; preserve "Page retained keys, query actual destination presence, snapshot matches, flag and confirm safe position; partial snapshot failure stops and retry rebuilds it."
- [X] T018 [US1] Implement table-owned archive loops in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`: reset transient counts, perform each streaming copy, release its reader, persist candidate position/count, and only then accept progress and continue; preserve configured batch sizes, skip flags, delays and recorded-count semantics, including successfully examined empty ranges. Preserve "Successful batch, reader released before checkpoint reuse" and stop immediately on copy/checkpoint failure without assuming rollback of durable destination rows.
- [X] T019 [US1] Implement table-owned purge effect/checkpoint loops in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, retaining incomplete-process reset rules, working-position ranges, captured-key joins, actual affected-row counts and configured delays; checkpoint successful effects before accepting candidate progress, tolerate already absent rows on retry, and preserve "Absent rows tolerated; no outside-set deletion or fabricated counts." Leave FK orchestration inside the execution boundary for US2 to harden.
- [X] T020 [US1] Implement owned phase/overall completion and normal working-table removal in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`: confirm every required batch/transition before later work, retain archive completion when combined purge fails, and remove working tables only after confirmed overall completion. Preserve "All required archive checkpoints confirmed", "Every required preceding transition succeeds", and "Overall completion confirmed"; a failed write stops sequencing, while later drop/disposal failure is returned without rewriting durable markers. Cleanup must retain incomplete processes and required working tables.
- [X] T021 [US1] Run the T008–T013 cases through `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` and explicitly selected SQL containers for `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`; record safe fixture IDs, independent before/failure/retry key sets, positions/counts/markers and working-table evidence in `specs/003-own-archiving-execution/validation.md`. Report unavailable SQL checks as unverified and keep the release gate open; do not substitute mocks for durability evidence.

**Checkpoint**: US1 can demonstrate safe batch/checkpoint recovery through one request. This is the first operator-visible increment; configured FK restoration safety still requires US2 before full-feature release.

---

## Phase 4: User Story 2 — Recover resources and constraints on failure (Priority: P1)

**Goal**: Release every acquired resource, restore possibly disabled source FKs before releasing their connections, and preserve primary/secondary error identity.

**Independent Test**: Fail source/destination opening after earlier allocations, delete/checkpoint operations with DisableFK enabled, partial disabling, restoration and disposal. Observe every cleanup attempt and error through the request; use independent SQL connections for enabled/trusted bits, durable markers and retained recovery state. Cleanup-only errors terminate, and failed restoration prevents new purge/overall completion.

### Tests for User Story 2

- [X] T022 [P] [US2] Add controlled initialization/resource cases in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` for source-open failure after configuration opens and destination-open failure after configuration/source open; assert disposal of every allocated handle, including the failed-open connection, no successful initialized group returned, and the opening failure remaining primary. Include success/no-work/unknown-group exits and parameter-setup, reader, command and bulk-copy cleanup paths.
- [X] T023 [US2] Add primary/secondary-error cases in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` covering operation plus restoration/disposal/logging failures, multiple independent disposal failures, cleanup-only failures and nested cleanup lists; assert original ErrorRecord/cause/stack identity as exposed by the request, complete ordered sanitized `Fast1Archiving.CleanupFailures` entries, continuing cleanup attempts, and failure after durable completion without erasing committed markers.
- [X] T024 [P] [US2] Add real SQL FK fixtures in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` for delete failure and separately post-delete checkpoint failure with DisableFK enabled, using unequal SourceTableId/ProcessStateId and multiple inbound source child FKs. Inspect each exact constraint's `is_disabled`/`is_not_trusted` through independent connections after failure and retry, assert enabled/nonvalidating restoration, retained incomplete state/working tables and no new purge/overall completion on failure; include initially disabled constraints under the existing enable scope and DisableFK-off zero-toggle coverage.
- [X] T025 [US2] Add real SQL partial-disable and restore-failure fixtures in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`: fail after one actual disable, and separately fail one restore while allowing another, both with and without an earlier operation error. Inject only at narrow private action seams while performing/observing real DDL; verify all possibly affected constraints receive independent restoration attempts before connection release, remaining restores proceed, diagnostic identities are actionable and failed restoration blocks new completion. Remove injections and retry without editing process state.

### Implementation for User Story 2

- [X] T026 [US2] Replace the defective `DisableEnableFK` model routing in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` with parameterized source metadata enumeration and validated/quoted per-constraint DDL; retain installed signatures in `Fast1data.SqlServer/schema/archiving/sprocs.sql` and require no schema upgrade. Capture distinct source database/child schema/table/FK identities and register the complete list before any disable, preserving "Scope is inbound source FKs referencing the configured source table, including initially disabled entries within the existing enable scope."
- [X] T027 [US2] Implement owned disable/restoration obligations in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`: disable with `NOCHECK`, restore each independently with `WITH NOCHECK CHECK CONSTRAINT` on success and every failing exit after disabling begins, and finish attempts before releasing required connections. Preserve "Partial failure retains all possibly affected entries for independent restoration before connection release.", "NOCHECK disables; WITH NOCHECK CHECK enables without establishing trust.", and "DisableFK off creates no toggle obligation." Skip even toggle-list acquisition when disabling is off.
- [X] T028 [US2] Gate new purge-complete/overall-complete writes and working-table removal on successful required restoration in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`; retain unfinished state/tables on restoration failure, report affected constraints, and keep attempting remaining independent restoration/resource releases. Processing success plus restoration failure must terminate; later disposal failure must not undo already committed completion.
- [X] T029 [US2] Finish error/logging propagation across `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` and `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1`: retain the original operation error when cleanup or logging fails, promote the first cleanup-only error otherwise, merge all nested safe action/group/table/process/resource/constraint contexts, and ensure logging never bypasses cleanup or leaks connection strings, credentials or sensitive SQL. Do not replace the primary with an unconditional aggregate exception.
- [X] T030 [US2] Run T022–T025 through `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` and selected SQL containers for `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1`; append cleanup-attempt order, primary/secondary error evidence, exact fixture constraint enabled/trusted observations, retained state and retry results to `specs/003-own-archiving-execution/validation.md`, distinguishing controlled proofs from real SQL proofs and unavailable checks.

**Checkpoint**: Both partial-open cases release acquired resources; FK obligations survive partial disabling and every relevant failure; cleanup cannot hide the operation error or produce false success.

---

## Phase 5: User Story 3 — Invoke execution without coordinating its internals (Priority: P2)

**Goal**: Maintain the existing request and modes while keeping progress, ordering and cleanup inside execution.

**Independent Test**: Invoke successful and failing runs with only existing connection/group/log inputs. Validate all modes, selection, table/batch order, delays and no-work cases; inspect the caller for zero progress/checkpoint/FK/disposal sequencing. Import the module in a fresh process and verify the unchanged public contract.

### Tests for User Story 3

- [X] T031 [P] [US3] Add request-contract tests in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` for public/private parameter compatibility, existing no-success-object behavior, and success/failure forwarding through one execution call; inspect the caller structure to establish zero progress reads/mutations, checkpoint writes, constraint restoration calls or disposal sequencing. Exercise unknown-group, empty-group and disabled/no-work paths through this same request.
- [X] T032 [P] [US3] Expand the compatibility SQL matrix in `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` for archive-only, purge-only, combined, inactive, both-disabled and empty captured sets; retain computed/rowversion exclusion, missing-column creation and destination schema/table preparation cases, and verify existing incomplete-state/schema/procedure compatibility without new installation steps.
- [X] T033 [US3] Add controlled traversal tests in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1` for supplied active-table order, both-disabled skipping, completion of group preparation/archive before purge, configured `PurgeOrder`, original key/data/purge batch settings, delays and reconciliation triggers, including existing purge-only preparation behavior. Do not assert new ordering guarantees for unordered inputs or tied purge-order values.

### Implementation for User Story 3

- [X] T034 [US3] Complete group/table orchestration integration in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` and keep `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1` limited to constructing the inert owner, requesting execution and handling outcome. Resolve compatibility gaps identified by T031–T033 while preserving "Active rows in supplied traversal; purge view sorted by PurgeOrder." and "Inactive tables are excluded and both-disabled skipped." Keep existing SourceTable configuration fields, names, executable KeyQuery semantics, PK/same-instance prerequisites and one-process-per-group restriction.
- [X] T035 [US3] Validate T031–T033 and fresh-process imports of `Fast1data.SqlServer/Fast1data.SqlServer.psd1`/`Fast1data.SqlServer/Fast1data.SqlServer.psm1`; verify unchanged `Invoke-Fast1Archiving` mandatory string/common parameters, explicit manifest export, PowerShell 7.6 Core/x64 platform declarations and dependency versions. Review the final caller against `specs/003-own-archiving-execution/contracts/archiving-execution.md` and append contract/mode/order results and limitations to `specs/003-own-archiving-execution/validation.md`.

**Checkpoint**: All three stories use the unchanged request and the caller supplies inputs without coordinating execution internals.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Align operator guidance and establish the implementation release evidence.

- [X] T036 [P] Update `Fast1Archiving.md` with independent effect/checkpoint commits, retained-set retries, incomplete-capture recreation, stable configuration/single-process restrictions, working-position rather than source-PK ranges, recorded totals that may lag effects, cleanup attempts versus success, primary/secondary diagnostics and hard-termination recovery. Correct the trust warning to identify inbound source child FKs and explain enabled/untrusted status, possible invalid historical rows and no automatic repair; retain PK/same-instance/permission/setup-order guidance and state that no persistence upgrade or distributed transaction is introduced.
- [X] T037 [P] Update comment-based help in `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1` for one-request ownership, failure/retry behavior, retained working sets, independently durable effects, cleanup error reporting and FK restoration limitations while preserving the command signature and avoiding new public inputs/exports/success objects.
- [X] T038 [P] Bring `specs/003-own-archiving-execution/quickstart.md` in line with the implemented controlled/SQL test setup, Pester container inputs, target guards, required permissions, fixture injection/teardown and independent evidence protocol; provide executable commands using locally supplied secrets, fresh-process imports and the supported runtime without committing credentials or treating excluded Integration tags as proof of no SQL access.
- [X] T039 Run `Invoke-ScriptAnalyzer` on every changed `.ps1`, `.psm1` and `.psd1`, including `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1`, `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`, `Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1` and both archiving test files, using repository settings when present; fix all new warnings/errors without disabling rules, check tab-indented multiline control flow, and record baseline findings or unavailable tooling in `specs/003-own-archiving-execution/validation.md`.
- [X] T040 Run affected shared-helper regressions using the current `Fast1data.SqlServer/tests/Audit.Common.Tests.ps1`, `Fast1data.SqlServer/tests/Audit.Windows.Tests.ps1`, `Fast1data.SqlServer/tests/Audit.Linux.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` paths after inspecting their setup requirements; add only focused helper-resource regression cases needed by the changed behavior in `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, never infer SQL isolation from tags, and record pass/fail/unverified results in `specs/003-own-archiving-execution/validation.md`.
- [X] T041 Execute final relevant controlled and explicitly targeted SQL suites following `specs/003-own-archiving-execution/quickstart.md`, verify import/class-loading on available supported x64 Windows/Linux/macOS hosts, and finalize `specs/003-own-archiving-execution/validation.md` with runtime/tool versions, safe fixture evidence and FR-001–015/SC-001–006 coverage. Separate passed, failed, skipped and unverified checks; missing required SQL durability/FK evidence, new analyzer findings or material integrity failures block release rather than being reported as successful.

---

## Dependencies & Execution Order

### Phase Dependencies

1. **Setup**: T001 and T002 can begin immediately in different test files. SQL fixtures must not run before T001's guards are in place and explicit disposable targets are supplied.
2. **Foundation**: T003 → T004 → T005 → T006 → T007. T005 uses the failure handling from T003 and the test seams from T002. This phase blocks story implementation and establishes the common request.
3. **US1 (P1)**: Write T008–T013 first; T014 → T015 → T016 → T017 → T018 → T019 → T020; validate in T021. Implementation uses one model file and must remain serial. T012 edits both test files and waits for earlier test-file edits.
4. **US2 (P1)**: Depends on the foundation and US1's purge/completion operations; write T022–T025 before T026 → T027 → T028 → T029; validate in T030. Controlled test authoring can start after foundation while US1 runs, but SQL-file/model edits must be coordinated and US2 completion requires US1.
5. **US3 (P2)**: Depends on owned transitions from US1 and guarded cleanup from US2. Write T031–T033 before T034; validate contract and all modes in T035.
6. **Polish**: T036–T038 can run together after story integration. T039 follows all PowerShell edits; T040 adds tests only where needed and any such additions must also receive T039 analysis. T041 closes the evidence record after all required checks; fixes require rerunning affected validation.

### User Story Dependency Graph

```text
T001 + T002
     |
     v
Foundation (T003–T007)
     |
     v
US1: durable effects/progress/retry (T008–T021)  <-- MVP validation point
     |
     v
US2: resources/FKs/errors (T022–T030)
     |
     v
US3: compatible one-request integration (T031–T035)
     |
     v
Guidance + final validation (T036–T041)
```

The stories share one execution model, so serial integration is intentional. Each story has an independent acceptance procedure through the same request; independently testable does not mean implementing competing edits to `ArchivingModel.psm1` concurrently.

### Within Each User Story

- Author regression/contract cases before changing the behavior; distinguish expected behavior failures from harness/import failures.
- Internal state/preparation precedes effect loops; effects precede confirmed progress; required restoration precedes new purge/overall completion; overall completion precedes normal table removal.
- Stop processing after a required transition failure; continue independent cleanup attempts and preserve the primary error.
- Retry through a fresh execution owner against persisted state; tests must not repair progress manually.
- Use independent SQL connections outside fixture-wide rollback transactions to observe durability; capture safe evidence before teardown.

### Parallel Opportunities

- Setup: T001 and T002 touch different test files.
- US1: T008 controlled ordering tests and T009 retained SQL fixtures can be authored together. Serialize subsequent edits to either test file; T012 needs both.
- US2: T022 controlled initialization tests and T024 SQL FK fixtures can be authored together. T023 follows T022 in the controlled file; T025 follows T024 in the SQL file.
- US3: T031 controlled boundary tests and T032 SQL compatibility cases can be authored together; T033 follows T031 in the controlled file.
- Polish: T036 operator guide, T037 public help and T038 validation guide touch different files. Analyzer checks follow all relevant edits.
- SQL fault-injection cases sharing test databases/procedures are serialized; use separate isolated fixture targets before considering parallel runs. No production concurrency is added.

## Parallel Example: User Story 1

```text
After T007, author together:
T008: controlled effect/checkpoint ordering — Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1
T009: retained copy/delete SQL interruptions — Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1
Join before T012, which updates both test files; model implementation remains serial.
```

## Parallel Example: User Story 2

```text
After US1 integration, author together:
T022: both partial-open/resource paths — Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1
T024: real source FK delete/checkpoint failures — Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1
Continue T023 after T022 and T025 after T024; join before model implementation.
```

## Parallel Example: User Story 3

```text
After US2 integration, author together:
T031: same-request boundary contract — Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1
T032: SQL mode/schema compatibility — Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1
Continue T033 after T031; join before T034 orchestration integration.
```

## Implementation Strategy

### MVP First (User Story 1)

1. Complete safe test setup and protected execution foundation.
2. Complete US1 effect/checkpoint/capture/reconciliation behavior.
3. Validate retained interruptions, post-effect checkpoint failures and stable-set retry with real SQL evidence at T021.
4. Treat this as the first review/demo increment. Full-feature release still requires US2's P1 constraint/resource guarantees and final acceptance gates.

### Incremental Delivery

1. Foundation gives every scenario one request and one protected lifetime.
2. US1 establishes durable recovery without an atomicity or exactly-once-count promise.
3. US2 completes source FK restoration, error precedence and resource failure guarantees; rerun US1 when shared paths change.
4. US3 closes all compatibility modes and verifies that caller sequencing has been absorbed.
5. Update help/guidance, analyze every changed PowerShell file, run affected regressions and close the real SQL evidence gate. Unavailable targets or platforms remain explicitly unverified.

### Requirement Coverage

| Requirements | Primary tasks |
| --- | --- |
| FR-001, FR-015; SC-005: owned execution and caller simplicity | T005–T007, T014–T020, T031, T034–T035 |
| FR-002, FR-014; SC-006: contract, modes, order and prerequisites | T013, T031–T038, T041 |
| FR-003, FR-006–007; SC-001, SC-006: capture, reconciliation, working-set lifecycle | T009–T020, T032 |
| FR-004–005; SC-001–002: effect/write/phase sequencing and independent commits | T008–T021, T028, T036–T038 |
| FR-008, FR-011; SC-003–004: resource ownership and primary/secondary failures | T003–T007, T022–T023, T027–T030 |
| FR-009–010; SC-003–004: source FK scope, partial disable, restoration and trust | T024–T030, T036–T037 |
| FR-012–013; all success criteria: retained/new tests and truthful SQL evidence | T001–T002, T008–T013, T021–T025, T030–T033, T035, T039–T041 |

## Notes

- **Total**: 41 tasks — setup 2, foundation 5, US1 14, US2 9, US3 5, polish 6.
- **Parallel markers**: 10 tasks across setup, story test-file pairs and final documentation; see the specific execution windows above.
- Generation of this checklist does not execute implementation, SQL fixtures, future-code analysis or release validation.
- No extension hooks are registered: `.specify/extensions.yml` was absent when this task list was generated.
