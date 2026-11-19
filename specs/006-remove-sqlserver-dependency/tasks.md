---
description: "Current implementation and acceptance tasks for the ConnStr migration executor"
---

# Tasks: Remove the SqlServer Module Dependency

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [migration-execution contract](contracts/migration-execution.md), [script-session contract](contracts/script-session.md), [required-library contract](contracts/required-library.md), and [quickstart.md](quickstart.md).

**Prerequisites**: Read `AGENTS.md` and `.specify/memory/constitution.md`. Constitution 1.1.0 and module 0.1.0 are already approved. Preserve working-tree edits, package versions, public parameters/exports, configuration, and history schema.

**Status and history**: Regenerated on 2026-11-19. Completion markers track the current implementation run; verification tasks do not imply delivered behavior needs rebuilding. IDs below form a new sequence scoped to this file. Earlier IDs in feature artifacts and historical validation belong to the previous task sequence; see the previous task ID mapping below for carried-forward obligations. Prior clone/restoration evidence does not establish FR-016 acceptance.

**Tests**: Explicitly required by the specification. Adapt existing tests rather than duplicate them; add uncovered cases before implementation and observe expected behavior failures. Missing tools/assets/SQL targets are limitations, not expected regression failures. Real SQL claims require explicitly selected disposable resources. Generation performs no implementation/runtime acceptance.

**Organization**: One phase per story, P1 before P2. Among P1 stories US6 precedes US2/US5 because its interface is needed for their acceptance. US1's import checkpoint is independently testable; its full public workflow requires executor/isolation/history integration.

## Format: `[ID] [P?] [Story] Description`

- Unchecked checkboxes, sequential IDs, optional `[P]`, story labels only in story phases, and exact repository-relative paths.
- `[P]` identifies distinct files in a documented execution wave after prerequisites. Examples describe scheduling and do not authorize delegation.
- Use tab-indented multiline PowerShell blocks; retain `.vscode/` tracking.
- Model state is transient; no new schema/configuration/persisted models/execution framework.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish current context while preserving governance and historical evidence.

- [X] T001 Append current Git status, host/tool versions, active constitution 1.1.0/module 0.1.0 approval, preserved package edits, current-versus-previous ID distinction, available SQL/native resources without secrets, and unrun checks to `specs/006-remove-sqlserver-dependency/validation.md`; retain all historical results.
- [X] T002 Review identity regressions in `Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1` and `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1`, recording invariants in `specs/006-remove-sqlserver-dependency/validation.md`: FullPath is "Existing phase evaluation; literal contained file path", ScriptName is "Existing normalized phase-relative identity with `/` separators", Phase is "Literal configured phase name", Checksum is "Existing SHA-256 over file bytes, represented by 64 characters", HistoryScriptName is "Exact stored key retained for a forced update", and IsForced/WasExecuted are "Existing evaluation flags; update only when both are true"; retain containment, case/separator, duplicates/conflicts, drift, ignore/force, reporting and order.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Prepare shared fixtures/dependencies before story implementation.

- [X] T003 Adapt `Fast1data.SqlServer/tests/fixtures/Get-MigrationTestCommand.ps1` for narrow owned-connection/command observations and deterministic creation/open/disposal failures without requiring caller resources; preserve history fixtures and temporary compatibility while consumers migrate. Fixture observations do not establish live provider/session/authentication correctness.
- [X] T004 Verify preserved net10.0/SqlClient 7.1.2/ScriptDom 180.154.0/Pkcs 11.0.0 in `build/SqlClientLoader.csproj`, both primary DLLs and transitive/native/resource output under `Fast1data.SqlServer/lib/win-x64/`, `Fast1data.SqlServer/lib/linux-x64/`, and `Fast1data.SqlServer/lib/osx-x64/`, and selected-distribution bootstrap in `Fast1data.SqlServer/tests/fixtures/Import-SharedHelperDependency.ps1`; rebuild via `build/build.ps1` only if required by missing/stale assets or findings, retaining versions/cleanup containment, and record readiness/blockers in `specs/006-remove-sqlserver-dependency/validation.md`.

**Checkpoint**: T001-T004 complete before story implementation. Bundles do not establish native acceptance; explicit SQL opt-in remains mandatory.

## Phase 3: User Story 1 - Run migrations without an extra PowerShell module (Priority: P1)

**Goal**: Retain import without SqlServer and bundled client/parser dependencies.

**Independent Test**: Fresh source root/manifest and eventual staged imports with SqlServer undiscoverable expose exactly Invoke-Fast1Audit, Invoke-Fast1Migration, Invoke-Fast1Archiving. Full story acceptance also requires public SQL migration/failure/retry after executor/history integration.

### Tests and retained implementation

- [X] T005 [P] [US1] Review/extend missing import/export assertions in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1`: no SqlServer prerequisite, no usable partial exports on faults, SqlClient then ScriptDom before behavior, selected-RID provenance, no migration Invoke-Sqlcmd execution, and retained generic-loader inventory.
- [X] T006 [P] [US1] Verify both-primary-DLL guards, recursive native/resource copies, contained cleanup and source validation before stage replacement in `build/build.ps1` and `out/publish.ps1`; fix demonstrated gaps only, without wider suppressions or claiming StageOnly as full release validation.
- [X] T007 [US1] Run source import cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, verify removed prerequisites/approved version/three exports in `Fast1data.SqlServer/Fast1data.SqlServer.psd1`, and record import/provenance evidence in `specs/006-remove-sqlserver-dependency/validation.md`; reserve full operator acceptance for T033/T040/T041.

**Checkpoint**: Source dependency removal verified; public migration acceptance remains dependent on the executor/history stories.

## Phase 4: User Story 6 - Invoke a script directly with a connection string (Priority: P1)

**Goal**: Replace executor borrowing with mandatory ConnStr and owned connection/command; retain SqlCmd history.

**Independent Test**: Invoke with only ConnStr/Script; inspect mandatory types, bad input rejection even for empty files without allocation, exact forwarding, timeout 0, owned resources and ordered cleanup. Live target/authentication follows in US5.

### Tests

- [X] T008 [P] [US6] Adapt `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1` for mandatory string ConnStr/existing Script, no executor SqlCmd/open-caller prerequisite, missing/null/empty/whitespace input, malformed syntax/unknown keywords/invalid typed values with empty/executable files, valid zero-batch success without login/allocation, original-string preservation and safe contextual errors retaining causes; observe relevant failures before T010.
- [X] T009 [P] [US6] Adapt `Fast1data.SqlServer/tests/Migration.Tests.ps1` for original ConnStr forwarding per file, unchanged history settings, no timeout switching/database restoration, executor-success/history/next-script order, stop on failure, no mutation-command allocation for preview/declined/invalid/empty/all-skipped work, and unchanged evaluation/reporting before confirmation; observe failures before T011.

### Implementation

- [X] T010 [US6] Replace signature/ownership in `Fast1data.SqlServer/private/migration/Invoke-Migration.ps1`: ConnStr is "Original caller-supplied string; forwarded unchanged to the executor, never included in contextual diagnostics" and ConnectionStringValidation is "Nonblank check and local SqlConnectionStringBuilder syntax/keyword/typed-value validation before zero-batch return; no execution connection/command or authentication probe". After complete script/span validation create suppression scope, initialize/open SqlConnection from the original string, create one owned command with timeout 0, retain batches/final transaction check, and dispose command then connection then scope on all exits using existing cleanup. Remove clone/history-database/binding/restoration and caller-transaction rejection; never touch history or allocate execution SQL resources for rejected/zero-batch files. Preserve resource rules: ExecutionConnection is "New target SqlConnection initialized from ConnStr and opened/disposed inside Invoke-Migration for one executable file"; ExecutionCommand is "Executor-created command reused across all file batches and final transaction check; disposed before its connection"; TargetServer/TargetDatabase are "Target configured by ConnStr, including its configured/default catalog behavior; no history-current-database snapshot"; AuthenticationConfiguration is "Connection-string authentication/options supplied by caller; no clone of external credential/token objects"; SuppressionScope is "Owned ambient suppression through script open/execution/SQL cleanup; disposed to restore ambient context".
- [X] T011 [US6] Update `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1` to forward original ConnStr and keep Set-Executed -SqlCmd on owned history resources; remove timeout switching, retain history timeout/confirmation/evaluation, create history resources only for confirmed eligible work, and attempt command then connection cleanup preserving the primary error.
- [X] T012 [US6] Run new-interface/public cases in `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1` and `Fast1data.SqlServer/tests/Migration.Tests.ps1`, inspect signatures in a fresh source process per `specs/006-remove-sqlserver-dependency/quickstart.md`, and record FR-016/SC-009 offline results in `specs/006-remove-sqlserver-dependency/validation.md`; synthetic authentication/target observations do not establish live acceptance.

**Checkpoint**: ConnStr executor/public forwarding implemented; only history borrows SqlCmd. Parser/session/live acceptance follows.

## Phase 5: User Story 2 - Execute migration batches faithfully (Priority: P1)

**Goal**: Preserve whole-file validation/original batches through ConnStr.

**Independent Test**: Offline boundary/preflight suites and direct SQL execution prove once-only order, definitions, within-file state, no effects for later syntax errors and no remaining work after runtime failure.

### Tests

- [X] T013 [P] [US2] Adapt `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1` to ConnStr, preserving mixed-case standalone GO, leading/trailing/consecutive separators, multiline/quoted/commented text, definitions, empty files and spans: Ordinal is "One-based executable-batch order within the script"; StartOffset/FragmentLength are "Valid in-range span from ScriptDom into the original source"; StartLine/StartColumn are "Original source coordinates for diagnostics"; Statements are "Parser AST statements; empty collection means no database execution"; CommandText is "Original substring; excludes separator tokens and preserves statement text".
- [X] T014 [P] [US2] Adapt `Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1` for ConnStr/no allocation on read/lexical/parse/span failure; retain later syntax errors, genuine GO 1/GO 3, SQLCMD/shell/utility directives outside literals/comments, harmless directive mentions inside them, reserved `$(Name)` everywhere including identifiers/comments, original coordinates, safe context/preserved causes and no partial-AST execution.
- [X] T015 [US2] Adapt direct cases in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` to ConnStr, adding only missing live order/once-only, definitions, temporary continuity, explicit QUOTED_IDENTIFIER, zero-batch, later-parse-error zero-effects and later-runtime-error partial-commit cases; retain FAST1_TEST_SQL_CONNECTION_STRING, unique disposable databases, case-sensitive coverage/cleanup and no hardcoded connection defaults.

### Retained implementation and acceptance

- [X] T016 [US2] Reconcile `Fast1data.SqlServer/private/migration/Invoke-Migration.ps1` with T013-T015, retaining literal-path full read/disposed reader and TSql160Parser($true): SourceText is "Complete file contents read for this attempt; transient", Batches are "Ordered parser batches with statements; zero or more", and ParseDiagnostics are "Original script coordinates and parser error identifiers; fatal if nonempty". Validate every span before allocation, execute original slices once with cleared parameters/text mode, discard results, retain safe script/stage/batch/source context and causes, and correct demonstrated regressions only.
- [X] T017 [US2] Run `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1`, and direct cases in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` with explicit SQL opt-in only; record boundary/zero-effects/runtime-failure outcomes or unavailable SQL checks in `specs/006-remove-sqlserver-dependency/validation.md`.

**Checkpoint**: Batches independently testable through ConnStr; unrun SQL cases remain open.

## Phase 6: User Story 5 - Isolate each script's database session (Priority: P1)

**Goal**: Prove target/session isolation and owned-resource completion barriers.

**Independent Test**: Compare concurrent script/history sessions, share state across GO, then check history/next-file target/settings under pooling. Initialization/execution/postflight/cleanup failures must prevent history/later work.

### Tests

- [X] T018 [P] [US5] Extend ConnStr lifecycle cases in `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1` for suppression/connection construction/open/command creation/batch/postflight failures, one command/session at timeout 0, balanced BEGIN/COMMIT or BEGIN/ROLLBACK, nonzero/failed transaction check, and no allocation/postflight for rejected/zero-batch files; FinalTransactionCount is "SELECT @@TRANCOUNT after executable batches on their owned command/session; must be zero". Replace clone/binding/assigned-executor-transaction assertions and observe uncovered failures before T021.
- [X] T019 [P] [US5] Adapt `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` for command then connection then scope disposal, each failure independently, operation plus multiple cleanup failures, cleanup-only termination, partial-initialization cleanup and ambient restoration; require every created resource to receive an attempt, preserve the first error with safe attached details and retain public/history cleanup without executor restoration expectations.
- [X] T020 [US5] Extend `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` for concurrent script/history separation, within-file continuity, temporary/settings/USE isolation across pooled files allowing physical SPID reuse, original-string configured/default catalog despite changed history database, original SQL-auth string despite history redaction, provisioned connection-string authentication, ambient suppression/restoration, balanced/unfinished transactions, and no history/next-file after postflight/cleanup failure with rollback/retry. External SqlCredential/token/callback objects are not inputs; unavailable modes remain unverified.

### Implementation refinements and acceptance

- [X] T021 [US5] Resolve T018-T020 lifecycle gaps in `Fast1data.SqlServer/private/migration/Invoke-Migration.ps1` using Close-GenericSqlResource/Add-GenericSqlCleanupFailure from `Fast1data.SqlServer/private/shared/GenericSqlCleanup.ps1`: CommandTimeout is "Execution command uses 0; history command retains its supplied value without switching", Transaction is "History writer preserves its assigned transaction; executor has no borrowed-command transaction input", CommandType is "Text for each operation", CommandText/Parameters are "Operation-specific; clear stale parameters before use", and PrimaryError is "First terminating operation failure, preserved across all owned cleanup attempts". Suppress ambient through SQL disposal; require zero final transactions and successful cleanup, never auto-commit/fall back to history, and exclude source/values/secrets from context.
- [X] T022 [US5] Run affected `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1` and `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` cases plus explicit-target pooled/authentication/ambient/transaction/failure cases in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`; record per-mode results/gaps in `specs/006-remove-sqlserver-dependency/validation.md`, without crediting clone probes/skips as current acceptance.

**Checkpoint**: Batches, transaction check and command/connection/scope cleanup all precede success; object observations do not replace live evidence.

## Phase 7: User Story 3 - Keep history resources reusable and separate from scripts (Priority: P2)

**Goal**: Preserve borrowed history settings/transactions and durable whole-script completion.

**Independent Test**: A real history command with nondefault timeout/transaction retains settings/lifetime and caller reuse/rollback; verify typed new/forced writes, public order, failure stops and retry.

### Tests

- [X] T023 [P] [US3] Retain/extend missing history-only cases in `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1`: mandatory typed SqlCmd, null/missing/closed-connection errors, no replacement/open/disposal/generic-query allocation, text/parameter replacement, preserved connection/timeout/transaction and exact parameter metadata; executor assertions retain ConnStr.
- [X] T024 [P] [US3] Extend `Fast1data.SqlServer/tests/Migration.Tests.ps1` for no history/next-script after any executor stage/cleanup failure, one history call after success including empty files, history failure stopping later work, unchanged force/ignore/phase/checksum/reporting/confirmation and public cleanup preserving the primary error.
- [X] T025 [US3] Adapt/complete `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` history/public cases: real history connection/timeout/transaction preservation/reuse/rollback, new/forced case-sensitive legacy keys, normalized name/checksum/database UTC time, missing forced key, unchanged failed-forced row/time, one row including empty scripts, failure stops, committed SQL then history failure, preview/declined/no-work effects, owner cleanup and idempotent retry.

### Retained implementation and acceptance

- [X] T026 [US3] Correct demonstrated regressions only in `Fast1data.SqlServer/private/migration/Set-Executed.ps1`: preserve borrowed resources/settings/transaction, clear parameters, execute once without allocation/disposal/generic query, retain HistoryScriptName default/missing-key failure and typed @script_name/@history_script_name NVarChar(255), @phase NVarChar(32), @checksum Char(64). Preserve model constraints: phase "nvarchar(32)" and "Composite primary key with script name"; script_name "nvarchar(255)" and "Normalized current name; forced lookup uses original persisted key"; checksum "char(64)" and "Successful script's SHA-256"; executed_at "datetime2(7)" and "Database `sysutcdatetime()` default on insert; refreshed on forced update". Leave `Fast1data.SqlServer/private/migration/Get-Executed.ps1` and schema unchanged. SqlCmd is "Caller/public-owned history command supplied only to Set-Executed" and HistoryConnection is "Existing open connection used only for history, not borrowed by the executor".
- [X] T027 [US3] Resolve T024/T025 completion/history-order regressions in `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1`; retain history-only ownership, original ConnStr forwarding, history after executor cleanup, termination on history failure and ordered unconditional owner cleanup without phase transactions/public parameter changes.
- [X] T028 [US3] Run `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1`, `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` and explicit-target history/public cases in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`; record FR-002/FR-003/FR-006 through FR-010 success/failure/forced/retry or unavailable SQL evidence in `specs/006-remove-sqlserver-dependency/validation.md`.

**Checkpoint**: Only history borrows resources; public completion follows executor cleanup and persistence.

## Phase 8: User Story 4 - Load required libraries through one reusable function (Priority: P2)

**Goal**: Retain/revalidate delivered generic loading after executor changes.

**Independent Test**: Fresh source/staged processes initialize SqlClient, ScriptDom and Microsoft.SqlServer.Server through one function; inspect reuse/types/identity/provenance and cold/warm faults without fallback/partial exports.

### Tests and retained implementation

- [X] T029 [P] [US4] Review/extend gaps in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1`: primary DLLs plus Microsoft.SqlServer.Server.dll/Microsoft.SqlServer.Server.SqlFunctionAttribute, omitted/multiple/case-sensitive types on initial/reused paths, invalid/escaping filenames, exact identity mismatches/renamed wrong DLLs, compatible reuse without output, incompatible preload rejection, cold/warm missing/corrupt selected assets and cold provenance; mutate marked disposable copies only.
- [X] T030 [P] [US4] Verify parameter-aware bootstrap tracing, complete private inventory (currently 23 files), root-private ownership and three exports in `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`, `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1`, `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1`, and `Fast1data.SqlServer/tests/fixtures/Import-SharedHelperDependency.ps1`; retain independent SqlClient initialization and no loading in ordinary behavior.
- [X] T031 [US4] Retain `Fast1data.SqlServer/private/shared/Import-RequiredLibrary.ps1` and SqlClient-then-ScriptDom bootstrap in `Fast1data.SqlServer/Fast1data.SqlServer.psm1`, correcting demonstrated gaps only: RequiredTypeName is "Optional fully qualified, case-sensitive type names; all must resolve from the chosen assembly", DistributionRoot is "Derived from the defining loader; never inferred from the working directory or source fallback", RuntimeIdentifier is "Existing runtime resolver: `win-x64`, `linux-x64`, or `osx-x64`", ExpectedPath is "Absolute selected-distribution `lib/<rid>/<DllName>`; literal file in that bundle", ExpectedIdentity is "Managed file metadata; simple name matches filename stem", ActualIdentity is "Name, version, culture, public-key token; must match `ExpectedIdentity`", and LoadDisposition is "Transient `Reused` or `Loaded`; internal observation, no success output". Enforce single-filename/nonempty-stem .dll rules, reject rooted/drive/separator/colon/wildcard/invalid filenames, validate the bundle every call, exact identity/types/cold location, conflicts without fallback/new load context, and safe DLL/RID/path/rebuild errors retaining causes; add no specific loader/allowlist/third-library production bootstrap/export. DllName follows "Mandatory, nonempty single filename with a nonempty stem and case-insensitive `.dll` extension."; Assembly is "Compatible preloaded instance or assembly loaded from `ExpectedPath`"; Diagnostics are "Requested DLL, RID/path when available, rebuild guidance, and preserved underlying exception".
- [X] T032 [US4] Run fresh source loader/fault/reuse/provenance and shared-helper cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`; record FR-014/SC-007 in `specs/006-remove-sqlserver-dependency/validation.md`, retaining staged/native obligations in T039/T041.

**Checkpoint**: Generic loading independently verified; no specific loader restored.

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Finish guidance and source/staged/SQL/native validation, recording limitations.

- [ ] T033 Run the complete source `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` matrix from `specs/006-remove-sqlserver-dependency/quickstart.md` on the explicitly selected disposable target: public migration without SqlServer, original-string target/authentication, pooling/ambient isolation, history transactions, completion barriers and failure/retry; record actual results/missing prerequisites in `specs/006-remove-sqlserver-dependency/validation.md`, leaving unavailable acceptance open.
- [X] T034 [P] Update help in `Fast1data.SqlServer/private/migration/Invoke-Migration.ps1` and `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1` for ConnStr, owned command/connection/scope, timeout 0, borrowed history/transactions, original forwarding, zero execution opens for rejected/empty files, ambient suppression, explicit transaction completion and cleanup-before-history; remove obsolete clone/binding/restoration/assigned-executor-transaction/timeout-switching guidance.
- [X] T035 [P] Reconcile `README.md`, `Fast1Migration.md`, and `Fast1data.SqlServer/Fast1data.SqlServer.psd1` release notes with generic loading/approved 0.1.0/removed prerequisite, ConnStr executor/SqlCmd history, TSql160/initial quoted identifiers/standalone GO, rejected preprocessing/substitution/counts, within-file continuity/pooled isolation, complete explicit transactions, partial commits/history failure and idempotent administrator-input retry; retain public/runtime contracts.
- [X] T036 [P] Reconcile `specs/006-remove-sqlserver-dependency/quickstart.md` with test names, current task IDs and previous ID mapping, source/staged commands, explicit SQL opt-in/provisioned authentication, full-release versus StageOnly, signature inspection and native obligations; retain historical evidence/no implicit targets.
- [X] T037 Import current dependencies and run Invoke-ScriptAnalyzer on all feature-changed/new .ps1/.psm1/.psd1 files including `build/build.ps1`, `out/publish.ps1`, module/tests/fixtures; use project settings when present, resolve introduced findings without suppressions, check `AGENTS.md` formatting and record unrelated warnings/unavailable analysis in `specs/006-remove-sqlserver-dependency/validation.md`.
- [X] T038 Run all source offline suites under `Fast1data.SqlServer/tests/` excluding `*.Integration.*`, including migration/phase/loader/shared-helper/cleanup/audit/archiving and all shared-helper scenarios; remove transitional compatibility from `Fast1data.SqlServer/tests/fixtures/Get-MigrationTestCommand.ps1` only after consumers migrate, resolve regressions and record fresh counts/skips in `specs/006-remove-sqlserver-dependency/validation.md`.
- [X] T039 Stage through `out/publish.ps1 -StageOnly` when full resources are unavailable; run affected offline suites/all shared-helper scenarios under `out/Fast1data.SqlServer/tests/`, fresh staged signature/root/manifest/import/export/loader/fault/provenance checks and both-primary/transitive/native/resource checks under `out/Fast1data.SqlServer/lib/win-x64/`, `out/Fast1data.SqlServer/lib/linux-x64/`, and `out/Fast1data.SqlServer/lib/osx-x64/`; record evidence in `specs/006-remove-sqlserver-dependency/validation.md`, without source/global fallback or claiming full release validation.
- [ ] T040 Review every integration suite's separate disposable-resource prerequisites under `Fast1data.SqlServer/tests/`, configure explicitly selected resources, run default `out/publish.ps1` and staged public migration/failure/retry against `out/Fast1data.SqlServer/Fast1data.SqlServer.psd1` without SqlServer; record full-suite/staged SQL outcomes/blockers in `specs/006-remove-sqlserver-dependency/validation.md`, without external publishing or running unrelated suites against embedded targets.
- [ ] T041 Repeat source/staged generic-loader and representative SQL acceptance from `specs/006-remove-sqlserver-dependency/quickstart.md` on native x64 Windows/Linux/macOS using their bundles; verify PowerShell 7.6+ Core/runtime, exports, provenance, target/authentication/ownership and audit's Windows/Linux restriction, recording per-host evidence/unavailable hosts in `specs/006-remove-sqlserver-dependency/validation.md`; cross-publishing/file presence are not native proof.
- [X] T042 Append a current FR-001 through FR-016, SC-001 through SC-009 and six-story evidence map to `specs/006-remove-sqlserver-dependency/validation.md`: approved versions, graph/build, source/staged/native/analyzer results, SQL authentication/session/transaction/failure/retry and task status; retain historical evidence, distinguish passes/skips/StageOnly/unrun obligations and keep material integrity risks as release blockers.

## Dependencies & Execution Order

### Phase dependencies and story completion graph

```text
Setup T001-T002 -> Foundation T003-T004
  -> US1 source import T005-T007
      -> US6 ConnStr input/caller T008-T012
          -> US2 batches T013-T017
              -> US5 lifecycle/isolation T018-T022
                  -> US3 history/completion T023-T028
  -> US4 loader regression T029-T032 (independent after foundation)
US1 import + US6 + US2 + US5 + US3 -> full public US1 acceptance T033
All stories -> guidance T034-T036 -> analyzer T037 -> offline T038
  -> staged T039 -> full release/staged SQL T040 -> native T041 -> evidence T042
```

- US6 requires foundation/US1 usable imports. T008/T009 fail meaningfully before T010/T011; both implementations precede T012.
- US2 requires ConnStr. T013/T014 precede any T016 correction; T015 precedes T017. Parsing remains execution-time validation, not a new preview syntax-validation guarantee.
- US5 requires US6 ownership/US2 batches. T018-T020 precede T021 refinement and T022 acceptance; completion barriers pass before successful history claims.
- US3 retains its writer but verifies public completion after US5. T023-T025 precede T026/T027 corrections and T028 acceptance.
- US4 can proceed independently after foundation with disjoint file ownership; finish US1's loader-test edits before US4 edits to those files. Complete distribution acceptance includes T032/T039/T041.
- T033/T040/T041 require provisioned environments. Missing resources leave those obligations open while independent guidance/offline/staging proceeds; T042 can record partial evidence. Never count skipped SQL/native obligations as complete.
- If T038 removes transitional compatibility, repeat affected analysis/tests before staging. Analyze/test subsequent PowerShell fixes before acceptance.
- Serialize edits to `Migration.Integration.Tests.ps1`, `Invoke-Migration.ps1`, `Invoke-Fast1Migration.ps1`, shared loader workers/tests and `validation.md`. Source/stage/fault mutations must inspect stable distributions.

### Parallel opportunities and examples per story

Seven waves contain 15 `[P]` tasks. Prerequisites still apply; evidence writes/distribution mutations are serialized.

| Story | Parallel wave | Follow-up |
|---|---|---|
| US1 | T005 loader tests/worker; T006 `build/build.ps1` and `out/publish.ps1` | T007 |
| US6 | T008 `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1`; T009 `Fast1data.SqlServer/tests/Migration.Tests.ps1` | T010-T012 |
| US2 | T013 `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1`; T014 `Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1` | T015-T017 |
| US5 | T018 `Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1`; T019 `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1` | T020-T022 |
| US3 | T023 `Fast1data.SqlServer/tests/Migration.Command.Tests.ps1`; T024 `Fast1data.SqlServer/tests/Migration.Tests.ps1` | T025-T028 |
| US4 | T029 module-loader tests/worker; T030 shared-helper tests/workers (distinct files listed above) | T031-T032 |
| Cross-cutting | T034 help; T035 README/guide/manifest; T036 quickstart | T037-T042 |

## Implementation Strategy

### MVP first

1. Verify setup/foundation and US1 source import without rebuilding delivered loading unnecessarily.
2. Implement US6 input/forwarding, preserve US2 parsing, establish US5 isolation/completion and US3 history integration.
3. Validate public multi-batch migration, one completion record, runtime/history failure stops and safe retry without SqlServer. This vertical slice is the operator MVP; import alone is insufficient.
4. Retain/revalidate US4 generic loading; finish staged/native/release acceptance before release readiness. No external publication is included.

### Incremental delivery

Validate helpers, then real SQL/session/history, then packaged public behavior. Retain identity/checksum/order/preview regressions. Record unavailable environments honestly while completing independent work.

### Previous task ID mapping

| Previous ID | Current obligations |
|---|---|
| T056 | T003, T008-T009, T013-T015, T018-T020, T023-T025 |
| T057 | T010-T011 and targeted corrections T016/T021/T026-T027 |
| T058 | T012/T017/T022/T028 and T033-T042 |
| T033 | T015/T017, T020/T022, T025/T028, full SQL matrix T033 |
| T038 | T039-T040 staging/full release/staged SQL |
| T039 | T041 native hosts |
| T052 | T020/T022/T033 live pooling/original-string authentication/ambient isolation; external-property cloning superseded |

## Task Summary and Format Validation

| Scope | IDs | Count |
|---|---|---:|
| Setup | T001-T002 | 2 |
| Foundation | T003-T004 | 2 |
| US1 (P1) | T005-T007 | 3 |
| US6 (P1) | T008-T012 | 5 |
| US2 (P1) | T013-T017 | 5 |
| US5 (P1) | T018-T022 | 5 |
| US3 (P2) | T023-T028 | 6 |
| US4 (P2) | T029-T032 | 4 |
| Polish | T033-T042 | 10 |
| Total | T001-T042 | 42 |

The generated list contains 42 tasks with unique sequential IDs, exact paths, and story labels in story phases only. Current completion is recorded below. Fifteen tasks carry `[P]` across seven waves. Each story has independent test criteria and the graph identifies public-workflow dependencies. Previous task counts recorded in validation.md are historical and excluded from current counts.

## Implementation status — 2026-11-19

39/42 current tasks completed. T033 (source live SQL), T040 (full release/staged
SQL) and T041 (native platform/SQL acceptance) remain open because their explicitly
selected resources are unavailable. T017/T022/T028 record unavailable SQL evidence,
not live passes. T039 is StageOnly plus separately executed staged offline suites.
See validation.md for current counts and the FR/SC/story evidence map. Previous
task IDs in the mapping above retain their original scope.
