---
description: "Implementation tasks for consolidated migration phase validation"
---

# Tasks: Consolidate Migration Phase Validation

**Input**: Design documents from `specs/002-consolidate-migration-phases/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/migration-command.md`, `quickstart.md`, and `.specify/memory/constitution.md`.

**Tests**: Required explicitly by FR-011–FR-012 and the feature input. Write the regression tests before the corresponding implementation and establish the expected behavioral failures. A Pester framework/import failure or zero executed tests is an unavailable check, not a successful regression test.

**Organization**: Tasks are grouped by user story. Phase tests use actual temporary files and supplied history without SQL. Command tests control existing execution/history boundaries while using the real evaluator. Tagged integration tests retain actual SQL execution and persistence assertions.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies tasks that can run concurrently with the explicitly listed partners after their prerequisites complete; they edit different files.
- `[US1]`–`[US4]` map to the four stories in `spec.md`.
- Paths are relative to the repository root. `specs/002-consolidate-migration-phases/validation.md` is a new implementation evidence file created by T001.
- Every changed PowerShell file, including tests, must use tab-indented multiline control flow with braces as specified in `AGENTS.md`.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the existing environment and evidence baseline without changing dependencies or database targets.

- [X] T001 Create `specs/002-consolidate-migration-phases/validation.md` with the revision/worktree, OS/architecture, PowerShell/Pester/PSScriptAnalyzer/SqlServer versions, discovered analyzer settings, source import/exports, and pre-change analyzer/nonintegration migration test results for `Fast1data.SqlServer/tests/Migration.Tests.ps1` and the planned production files in `plan.md`; use the compatible Pester configuration described in `quickstart.md`, retain TestDrive, record framework failures separately, and record SQL/other-host checks as pending without printing secrets.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Provide isolated filesystem tests and explicitly targeted integration fixtures. Complete this phase before story implementation.

- [X] T002 [P] Create the phase-test harness in `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` with temporary literal configuration/file fixtures and supplied history; load only `private/migration/Resolve-MigrationPhase.ps1`, `private/shared/Get-FileChecksum.ps1`, and `private/shared/Get-RelativePath.ps1` rather than importing SQL runtime assets, and prepare assertions for empty/single/multiple decision arrays without creating a placeholder production evaluator.
- [X] T003 [P] **Reverted at user request**: Restore the original local `pester_migration` connection in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`; remove the added file-level `ConnectionString` parameter and missing-connection/catalog guards. Retain expanded coverage, nonintegration isolation, Integration-only SQL/schema setup, and fixture-owned cleanup. No database is created automatically.

**Checkpoint**: Harnesses support the planned boundaries. Until T007 creates the evaluator, phase-test failure due to its absence is expected and must be distinguished from behavioral assertions.

## Phase 3: User Story 1 — Interpret a phase consistently (Priority: P1) — MVP

**Goal**: One private phase interface interprets configuration, history, and selections consistently and returns ordered run/skip decisions without deployment.

**Independent Test**: Run `Migration.Phase.Tests.ps1` against nonalphabetical nested scripts, real SHA-256 content, supplied case/slash variants, and empty/single/multiple results. Confirm literal phase selection, normalized identities, expected reasons/order, duplicate/conflict rejection, warnings, and no SQL/execution/history calls.

### Tests for User Story 1

- [X] T004 [US1] Add selection/identity regression cases in `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` for literal bracketed phase/script names, exclusion of other phases, configured nonalphabetical order, empty versus missing phase, missing configuration/directory, and case/backslash/forward-slash variants across configuration/history/ignore/force; cover normalized duplicates, conflicts including unknown names, distinct unknown-ignore/unknown-force warnings, history-only entries adding no work, and contained rooted names from every source converted to phase-relative identity without general relative-path alias deduplication.
- [X] T005 [US1] Add decision-contract cases in `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` for new, unchanged historical, forced historical, forced new, ignored, and unforced changed scripts using real files/checksums; assert exact stored history spelling is retained, configured filesystem casing is preserved, ignored checksums are null, ordered warnings/decisions remain arrays for zero/one/many entries, and each non-ignored configured file is hashed once while ignored files are never hashed.

### Implementation for User Story 1

- [X] T006 [P] [US1] Change `Fast1data.SqlServer/private/shared/Get-FileChecksum.ps1` to use `Get-FileHash -LiteralPath` while retaining SHA-256 and the existing helper signature, so bracketed phase/script names are hashed as actual files.
- [X] T007 [P] [US1] Create `Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1` with `BasePath`, `Phase`, supplied `History`, optional `IgnoreScripts`, and optional `ForceScripts`, accepting empty collections and reading configuration once with literal operations; implement the model constraints `Phase`: "Literal selected JSON property name; do not interpret wildcard characters.", `ConfigFile`: "Absolute path to existing `migration.json`. Missing configuration terminates evaluation.", `PhaseDirectory`: "Absolute existing directory for the selected phase.", and `ConfiguredScripts`: "Ordered names from the phase's `scripts` array. An existing empty array is valid; a missing phase is an error."; emit actionable missing-input errors and introduce no SQL or public export.
- [X] T008 [US1] Implement shared name handling inside `Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1` using slash normalization and ordinal case-insensitive indexed sets/maps across all four name sources; preserve file-lookup spelling, convert contained rooted names with retained `Get-RelativePath`, preserve relative spelling, reject configured duplicates and global ignore/force intersections before eligibility, retain original matched history keys, and collect ordered unknown-selection warnings without adding scripts or using database collation for matching.
- [X] T009 [US1] Complete ordered checksum/eligibility decisions and the returned snapshot in `Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1` using the retained checksum helper after file checks; implement `ScriptName`: "Normalized phase-relative identity, display name, and intended persisted name.", `Checksum`: "Current SHA-256 for every non-ignored file; null for ignored entries.", `WasExecuted`: "Whether supplied phase history matched this identity.", `HistoryScriptName`: "Original matched persisted name for update lookup; null when no history matches.", and `IsForced`: "Whether the identity is in the force set."; restrict `Action` to `Run` or `Skip` and `Reason` to `New`, `Forced`, `Ignored`, `AlreadyExecuted`, reject unforced drift with identity/expected/current checksums, and return one object with metadata plus explicit ordered `Scripts`/`Warnings` arrays only after successful evaluation, without execution or history mutation.
- [X] T010 [US1] Run the US1 cases in `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` independently of SQL, verify actual bracketed-file hashing and the decision schema against `specs/002-consolidate-migration-phases/data-model.md`, and record executed/passed/failed/unavailable counts and exact commands in `specs/002-consolidate-migration-phases/validation.md`.

**Checkpoint**: The phase interface is independently usable and testable. US2 completes the adversarial containment and public-command preflight guarantees before operational use.

## Phase 4: User Story 2 — Detect phase problems before applying changes (Priority: P1)

**Goal**: Reject every invalid selected phase before the public command executes its first script or writes history.

**Independent Test**: Place a valid file first and each invalid condition later. Through the evaluator and public command, confirm terminating errors and zero executable partial results, executions, and history writes. Repeat command guards in execution and WhatIf modes.

### Tests for User Story 2

- [X] T011 [P] [US2] Add containment and atomic-evaluation cases in `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` for parent traversal, absolute external files, sibling-prefix escapes, the phase directory itself, ignored/forced escapes, missing non-ignored files including forced files, and contained ignored missing/drifted files; test valid-first/invalid-later duplicates, selection conflicts, escapes, missing files, and checksum drift, asserting no partial evaluation is emitted and diagnostics identify the violated rule; include host-appropriate path comparisons and file-casing cases.
- [X] T012 [P] [US2] Add public-command preflight guard cases in `Fast1data.SqlServer/tests/Migration.Tests.ps1` using real evaluator/files and controlled `Get-Executed`, `Invoke-Migration`, and `Set-Executed` boundaries; for missing inputs and every late-invalid class from T011, assert the expected terminating error and zero mutating helper calls in normal and WhatIf requests rather than mocking phase decisions.

### Implementation for User Story 2

- [X] T013 [US2] Enforce rooted-aware full-path resolution and separator-boundary containment in `Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1` before ignored/forced exemptions, implementing `FullPath`: "Absolute file location retaining configured filesystem casing. Must be strictly inside the phase directory, even when ignored." with Windows ordinal case-insensitive versus Unix ordinal comparison; require every non-ignored entry to exist as a file, exempt contained ignored entries from existence/hash checks, and buffer the entire evaluation so all late errors terminate without exposing partial decisions.
- [X] T014 [US2] Replace interleaved phase rules in `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1` with one history read and one completed `Resolve-MigrationPhase` call before `ShouldProcess` or mutation; consume returned order, paths, names, checksums, flags, and warnings directly, retain the existing execution/history helpers, and invoke each eligible execution then its history write with terminating errors while removing caller-side duplicate normalization, containment, and checksum decisions.
- [X] T015 [US2] Remove `Fast1data.SqlServer/private/migration/Get-Migration.ps1` after T014 and replace its obsolete reader-specific cases in `Fast1data.SqlServer/tests/Migration.Tests.ps1` with the phase/public-command assertions now provided; search `Fast1data.SqlServer/` for remaining runtime/test callers and keep the existing recursive private loader and manifest exports compatible.
- [X] T016 [US2] Run the phase and nonintegration command guard cases in `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Tests.ps1`, proving every late-invalid phase makes zero execution/history calls in both modes, and record evidence for FR-005–FR-007 and SC-002 in `specs/002-consolidate-migration-phases/validation.md`.

**Checkpoint**: Public execution cannot begin from a partially validated phase. US3 completes preview presentation/parity; US4 completes exact-key persistence and recovery verification.

## Phase 5: User Story 3 — Preview the same decisions used for execution (Priority: P2)

**Goal**: Preview reports the same ordered eligibility, skips, warnings, and failures while performing no mutations; valid no-work phases succeed clearly.

**Independent Test**: Compare normal and WhatIf requests against reset identical files/history for mixed new/unchanged/ignored/forced scripts and invalid phases. Assert matching diagnostics/ordered eligibility, allowed history reads, zero preview mutating calls, and `Nothing to run` for empty/all-skipped phases.

### Tests for User Story 3

- [X] T017 [US3] Add paired normal/WhatIf contract cases in `Fast1data.SqlServer/tests/Migration.Tests.ps1` for mixed decisions, forced historical/new scripts, unknown-selection warnings, identical validation failures, empty/all-skipped phases, and declined confirmation at the existing ShouldProcess boundary; assert history reads remain allowed, eligible names and skips appear in configured order, no-work diagnostics are present, and preview/declined requests call neither mutating helper; add an `Integration` WhatIf case in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` snapshotting real SQL effects and history count/name/checksum/timestamp before and after preview, including force.

### Implementation for User Story 3

- [X] T018 [P] [US3] Finish evaluation presentation and the existing phase-level `ShouldProcess` flow in `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1` so warnings, ordered eligible names, skip reasons, and `Nothing to run` derive from the same completed result in both modes; permit required reads/validation under WhatIf, gate both mutation helpers on approval, preserve common parameters, and keep diagnostics free of connection-string secrets.
- [X] T019 [P] [US3] Update `Fast1Migration.md` with whole-phase preflight, literal phase selection, case/separator matching, unknown-selection warnings, ignored-path containment, host-correct file casing, WhatIf history/file reads and ordered reporting, and empty/all-skipped behavior; explain that evaluation does not lock files or history while retaining setup order and executable-administrator-input guidance.
- [X] T020 [US3] Run paired preview/normal cases in `Fast1data.SqlServer/tests/Migration.Tests.ps1`, record ordered decisions/warnings/errors and zero-preview-mutation assertions in `specs/002-consolidate-migration-phases/validation.md`, and run the tagged real-history preview case in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` only against the explicitly supplied disposable database or record it as unrun.

**Checkpoint**: Preview and execution use identical phase decisions and validation; no-work and declined requests have no mutations.

## Phase 6: User Story 4 — Preserve truthful history across failures (Priority: P2)

**Goal**: Record successful work in order, update legacy stored keys correctly, and stop on execution or recording failure while retaining earlier progress and honest retry guidance.

**Independent Test**: Controlled boundary traces prove execute/write ordering and stopping behavior. Actual SQL assertions prove insert/update/skip, checksum/timestamp changes, legacy separator/case lookup, durable earlier progress, actual execution and recording errors, and safe idempotent retry. Case-sensitive database verification is explicit and never inferred from a case-insensitive database.

### Tests for User Story 4

- [X] T021 [US4] Add controlled coordination/failure regressions in `Fast1data.SqlServer/tests/Migration.Tests.ps1` for configured execute/write/next ordering, new/forced-new inserts, forced historical updates carrying the original stored key and normalized new name, and skips making no write; inject execution and recording failures separately, asserting terminating errors, no failed-execution record, no later script/write, earlier successful history retained, and retry eligibility after execution succeeds but recording fails.
- [X] T022 [US4] Extend tagged real SQL success coverage in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` while retaining the idempotent execute/record/skip/force case: assert ordered multi-script effects/history, unchanged skip checksums/timestamps, changed forced reruns updating name/checksum/database time without duplicate rows, forced-new insertion, and legacy backslash/case-variant original-key updates; record database collation and include the same legacy-key assertions on an explicitly selected case-sensitive-collation database, reporting that case unrun if unavailable.
- [X] T023 [US4] Add tagged real SQL failure/retry coverage in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`: make a later script fail in actual SQL and prove earlier effects/history survive with no later work; make an idempotent forced script remove only its own seeded history row after creating its SQL effect so recording raises the existing missing-row error, then assert surfaced error, no later work, retained earlier progress, and safe retry with truthful insertion/history; use fixture-owned cleanup and no mocked persistence assertions.

### Implementation for User Story 4

- [X] T024 [P] [US4] Update `Fast1data.SqlServer/private/migration/Get-Executed.ps1` to return the original `script_name` spelling instead of normalizing it, preserving the model constraint "Original stored key, preserved exactly until a write locates it."; retain the existing parameterized selected-phase SQL read, resource disposal, checksum value, and private interface, and update its help to describe raw stored names.
- [X] T025 [P] [US4] Extend only the existing private writer in `Fast1data.SqlServer/private/migration/Set-Executed.ps1` with `HistoryScriptName` for forced update lookup; parameterize the original-key predicate and normalized `ScriptName` assignment, preserve `phase` as `nvarchar(32)`, `script_name` as `nvarchar(255)`, `checksum` as `char(64)`, and `executed_at` as `datetime2(7)` with "Database UTC timestamp; default on insert, refreshed on forced update."; retain new/forced-new inserts, the missing-row terminating error, disposal, and the existing schema without a new database adapter.
- [X] T026 [US4] Pass evaluated `HistoryScriptName`, normalized name, checksum, phase, and the forced-and-historical update flag to the existing writer in `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1`; ensure each execution completes before its own history write and before the next script, propagate execution/recording errors immediately, and retain `Fast1data.SqlServer/private/migration/Invoke-Migration.ps1` with terminating `Invoke-Sqlcmd -AbortOnError -ErrorAction Stop` behavior rather than adding transactions, retries, or rollback claims.
- [X] T027 [P] [US4] Update failure/recovery guidance in `Fast1Migration.md` to require idempotent scripts and explain successful SQL followed by failed history recording, earlier durable progress, termination before later work, and potential re-execution on retry; describe normalized stored names and forced updates locating legacy original keys, retaining documented schema setup/permissions and explicit test-database selection without committed secrets.
- [X] T028 [US4] Run controlled history/failure tests and the retained/expanded `Integration` cases in `Fast1data.SqlServer/tests/Migration.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` against explicitly supplied disposable databases, recording insert/update/skip timestamps, original-key/collation evidence, failure/retry results, and unavailable SQL cases separately in `specs/002-consolidate-migration-phases/validation.md`; do not treat mocks as proof of SQL persistence or report unavailable databases as passing.

**Checkpoint**: Each story has acceptance evidence at its appropriate layer. Any unavailable SQL/platform check remains visible; unresolved material integrity failures prevent release.

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Align documentation, verify compatibility, and finish the constitution's validation gates across all stories.

- [X] T029 Align comment-based help in `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1`, `Fast1Migration.md`, and `specs/002-consolidate-migration-phases/quickstart.md` with the final command contract and runnable test commands; check literal names, normalized identity, whole-phase validation, ignored/forced limits, preview reads, setup/permissions, executable administrator inputs, and idempotent recovery without claiming atomicity or changed public parameters.
- [X] T030 Verify source import, public parameters, and the exact existing exports in `Fast1data.SqlServer/Fast1data.SqlServer.psd1` and `Fast1data.SqlServer/Fast1data.SqlServer.psm1`; confirm the evaluator remains private, no runtime/test `Get-Migration` callers remain, and `Fast1data.SqlServer/schema/migration/tables.sql`, dependencies, PowerShell 7.4 baseline, and supported platforms remain compatible; record checks in `specs/002-consolidate-migration-phases/validation.md` without changing these contracts.
- [X] T031 Run `Invoke-ScriptAnalyzer` on every added/modified PowerShell file, including `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`, with repository settings when available; compare T001's baseline, resolve all introduced errors/warnings without bypass suppressions, check tab-indented multiline control flow and `git diff --check`, and record exact file scope/settings/findings or explicit analyzer unavailability in `specs/002-consolidate-migration-phases/validation.md`.
- [X] T032 Run the complete affected phase, nonintegration command, and tagged SQL suites from `specs/002-consolidate-migration-phases/quickstart.md` after final edits; verify platform-sensitive containment, literal/bracketed paths, case-sensitive filesystem lookup, and supported PowerShell behavior on Windows/Linux/macOS where available, and record host/runtime/database/collation plus passed/failed/skipped/unrun counts and commands in `specs/002-consolidate-migration-phases/validation.md` without repeating unchanged passing checks unnecessarily.
- [X] T033 Complete the FR-001–FR-012 and SC-001–SC-005 evidence mapping in `specs/002-consolidate-migration-phases/validation.md`, distinguishing behavioral failures, framework failures, unrelated analyzer baseline findings, and unavailable SQL/platform checks; review the final implementation against `specs/002-consolidate-migration-phases/spec.md`, `plan.md`, and `.specify/memory/constitution.md`, document remaining limitations, and block release for unresolved material data-integrity failures.

## Dependencies & Execution Order

### Phase Dependencies

```text
T001 Setup
  └─ T002 + T003 Foundation (parallel, separate test files)
       └─ US1: T004–T010
            └─ US2: T011–T016
                 ├─ US3: T017–T020
                 └─ US4: T021–T028
                      └─ Both US3 + US4 complete → T029–T033 Polish
```

The default execution order follows task IDs and story priority. US3 and US4 share the public command, command test file, documentation, and evidence file: schedule their edits sequentially even though neither story's rules depend on the other. The graph describes prerequisites, not permission to edit shared files concurrently.

### User Story Dependencies

| Story | Requires | Independently assessed outcome |
| --- | --- | --- |
| US1 (P1) | Setup and foundation | Phase interpretation and decisions with temporary files/supplied history, no SQL deployment. |
| US2 (P1) | US1 evaluator | Adversarial phase rejection and public zero-mutation guards, no preview presentation or real persistence prerequisite. |
| US3 (P2) | US2 public evaluator integration | Preview/execution parity and no-work/confirmation behavior; SQL preview is an additional integration gate. |
| US4 (P2) | US2 public evaluator integration | Ordered persistence and failure/retry behavior, controlled independently of preview cases and verified with real SQL. |

US2 deliberately builds on US1's shared evaluator; duplicating it to make these stories structurally independent would contradict FR-001. US3 and US4 have independently runnable acceptance cases after that shared boundary exists.

### Within Each User Story

- Add the listed tests before the implementation they constrain. Once the boundary exists, confirm behavioral assertions fail for the intended reason before fixing them.
- US1: T004–T005 precede T006/T007; T008 follows T007; T009 follows T006 and T008; T010 verifies the completed increment.
- US2: T011/T012 precede T013; T014 follows T013; T015 follows T014; T016 verifies the combined preflight boundary.
- US3: T017 precedes T018/T019; T020 verifies the completed behavior and records any unavailable SQL preview check.
- US4: T021–T023 precede T024/T025/T027; T026 follows T024 and T025; T028 verifies persistence and recovery after implementation/docs complete.
- Real SQL execution requires an explicitly selected disposable database and fixture permissions from `quickstart.md`. Absence of that prerequisite leaves those checks unrun; it does not prevent writing fixtures or running isolated checks.
- Run story checks at their checkpoint. T032 broadens coverage to the complete affected suites and available platforms after final edits; unchanged passing checks need not be rerun between unrelated documentation edits.

### Parallel Opportunities

Only the following marked sets are parallel execution candidates; each set requires its preceding phase/story tests to be complete. This is an implementation scheduling guide, not an instruction to launch agents during task generation.

| Work set | Tasks | Separate files / prerequisite |
| --- | --- | --- |
| Foundation | T002, T003 | Phase test harness versus command/integration harness, after T001. |
| US1 implementation | T006, T007 | Checksum helper versus new evaluator metadata, after T005. |
| US2 regressions | T011, T012 | Phase tests versus command tests, after US1. |
| US3 implementation/docs | T018, T019 | Public command versus migration guide, after T017. |
| US4 persistence/docs | T024, T025, T027 | History reader, history writer, migration guide, after T023. |

Evidence-file updates and tasks touching the same test/command/documentation file are sequential. T026 waits for both reader and writer changes.

## Parallel Example: User Story 1

After T004–T005:

```text
T006: Use literal SHA-256 hashing in Fast1data.SqlServer/private/shared/Get-FileChecksum.ps1.
T007: Create phase metadata/input handling in Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1.
Then complete T008–T010 in dependency order.
```

## Parallel Example: User Story 2

After US1:

```text
T011: Add containment/buffering tests in Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1.
T012: Add public late-invalid zero-mutation tests in Fast1data.SqlServer/tests/Migration.Tests.ps1.
Then complete T013–T016 in dependency order.
```

## Parallel Example: User Story 3

After T017:

```text
T018: Implement shared preview presentation/approval in Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1.
T019: Document preflight and preview in Fast1Migration.md.
Then run T020.
```

## Parallel Example: User Story 4

After T021–T023:

```text
T024: Preserve stored keys in Fast1data.SqlServer/private/migration/Get-Executed.ps1.
T025: Update by the original key in Fast1data.SqlServer/private/migration/Set-Executed.ps1.
T027: Explain history failure and idempotent retry in Fast1Migration.md.
Then complete T026 and T028 after their prerequisites.
```

## Implementation Strategy

### MVP First (User Story 1)

Complete T001–T010 and demonstrate the private evaluator using real files and supplied history. This is a reviewable phase-interpretation MVP. Complete the remaining preflight, preview, and persistence gates before presenting the full public-command change as ready for operational release.

### Incremental Delivery

1. Establish environment evidence and safe test harnesses.
2. Deliver US1's ordered, normalized evaluator and isolated phase verification.
3. Deliver US2's containment/whole-phase rejection and replace/remove the shallow reader in the command path.
4. Deliver US3's observable preview parity and no-work behavior.
5. Deliver US4's original-key history writes, actual SQL failures, and idempotent recovery evidence.
6. Complete documentation, compatibility, analyzer, affected regression, and constitution review gates; report unavailable checks explicitly.

### Scope and Completion Notes

- Retain meaningful checksum, relative-path, SQL execution, and history helpers. Do not introduce a public phase API, database adapter, new dependency/schema, alias/history repair, symbolic-link policy, concurrency feature, transaction, or rollback promise.
- Model constraints are quoted in the implementation tasks that own them; SQL lengths/types preserve existing storage rather than introducing new schema validation policy.
- All 33 tasks start unchecked. Story counts: US1 = 7, US2 = 6, US3 = 4, US4 = 8; setup/foundation = 3; polish = 5. There are 11 `[P]` tasks across five parallel work sets.
- A completed evaluation is eligibility evidence, not completed work. Only successfully recorded execution establishes durable history; failed or unavailable verification must remain visible.
