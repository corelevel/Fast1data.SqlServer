---
description: "Implementation tasks for explicit module loaders and one shared loading list"
---

# Tasks: Explicit Module Loaders and One Shared Loading List

**Input**: Design documents from `specs/005-explicit-module-loaders/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/loader-boundaries.md`, `quickstart.md`, and `.specify/memory/constitution.md`.

**Tests**: The specification explicitly requires loader, import, isolation, operational regression, and source/package acceptance coverage. Add story-specific assertions before their corresponding implementation; confirm new assertions expose the pre-change defect. Reuse existing workflow suites rather than duplicate their cases.

**Organization**: Tasks are grouped by user story. Shared-loader integration requires removing private discovery in US1 so the new loader is not executed accidentally a second time in root. US2 builds on those entry points to finish dependency boundaries and failure handling. Each story has its own validation checkpoint; full feature acceptance requires all three.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies tasks that can overlap with another task in the same documented execution wave, after that wave's prerequisites are complete.
- `[US1]`, `[US2]`, and `[US3]` map to the specification's user stories. Setup, foundational, and polish tasks have no story label.
- Every task names its implementation, test, documentation, or evidence file. Keep checkboxes unchecked until implementation and applicable verification finish.

## Path Conventions

- Production module: `Fast1data.SqlServer/`; private paths below are relative to the repository root.
- Tests and reusable workers: `Fast1data.SqlServer/tests/` and `Fast1data.SqlServer/tests/fixtures/`.
- Staged distribution: `out/Fast1data.SqlServer/`; packaging entry point: `out/publish.ps1`.
- Execution evidence: create `specs/005-explicit-module-loaders/validation.md`. Record results there without credentials or connection secrets.
- Preserve existing edits in `Fast1data.SqlServer/Fast1data.SqlServer.psm1`, `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, and `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`; use the current working tree as the implementation baseline. Stay on the existing `dev` branch.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a reproducible baseline and confirm prerequisites without changing workflow behavior.

- [X] T001 Create `specs/005-explicit-module-loaders/validation.md` with the revision, existing working-tree edits, the 21-file private inventory from `research.md`, intended owners, and an FR-001–009/SC-001–004 evidence checklist; distinguish the recorded planning probes and four-test audit baseline from checks run during implementation.
- [X] T002 Verify PowerShell 7.6+ Core, Pester 6+, PSScriptAnalyzer, SqlServer, and `Fast1data.SqlServer/lib/win-x64/Microsoft.Data.SqlClient.dll`, `Fast1data.SqlServer/lib/linux-x64/Microsoft.Data.SqlClient.dll`, and `Fast1data.SqlServer/lib/osx-x64/Microsoft.Data.SqlClient.dll`; record tool versions, host, analyzer settings if present, and local SQL/audit fixture prerequisites in `specs/005-explicit-module-loaders/validation.md`; use `build/build.ps1` only if existing assets need rebuilding, preserving dependency versions and runtime identifiers.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Provide independent-process test infrastructure shared by all stories. Complete this phase before story work.

- [X] T003 Add `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1` as a fresh-process worker accepting an absolute distribution root and a named scenario; support cold direct-psm1 and manifest imports, explicitly bootstrapped model-first imports, disposable-copy instrumentation/fault scenarios, structured observations, captured original errors/preferences, and a failing exit code on unmet expectations; keep cold paths free of SqlServer/SqlClient preloading and locate fixtures only under the selected distribution.
- [X] T004 Create the common harness in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` to invoke T003 using the current host's `pwsh -NoLogo -NoProfile`, make fault copies under Pester TestDrive, assert worker exit/result completeness, and group acceptance tests with US1/US2/US3 tags; never remove/corrupt dependencies in the working source or reuse a process across independent import cases.

**Checkpoint**: The harness can run a no-fault worker against the selected distribution, report failures faithfully, and isolate filesystem mutations and process state. Story assertions follow in their respective phases.

---

## Phase 3: User Story 1 — Maintain the shared function list once (Priority: P1) — MVP

**Goal**: One authoritative five-file list supplies eight private shared functions independently to root and model.

**Independent Test**: In fresh root-first and explicitly bootstrapped model-first processes, inspect both consumers and the shared list. Each consumer owns all eight functions; the initial root-plus-model load executes the shared loader exactly twice, produces no operational output, and preserves the other consumer's definitions. Updating a disposable shared list requires no consumer-list changes.

### Tests for User Story 1

- [X] T005 [P] [US1] Add shared-list contract assertions in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`: one production selection list, both consumer dot-sources, ordered five-file/eight-function membership, two instrumented initial executions in distinct scopes, no initialization SQL/messages, and a disposable list-extension probe requiring no entry-point edits; enforce Identity "Root Fast1data.SqlServer or ArchivingModel", "Preserve two independent behavior module session states", and "Function Module and SessionState identify the intended consumer" from `data-model.md`.
- [X] T006 [P] [US1] Correct ownership expectations in `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1`: the shared set is logging, two query functions, three cleanup functions, checksum, and relative path; comparison/delay and seven model-local functions are model-only, while bootstrap/audit/migration/adapter functions are root-only; retain reference-identity assertions and enforce "Every loaded private file/module comes from the selected distribution" without changing the fixed public-contract snapshot or weakening existing cases.

### Implementation for User Story 1

- [X] T007 [US1] Add `Fast1data.SqlServer/private/shared/Load.ps1` with literal, loader-relative dot-sources in this exact order: `GenericSqlCleanup.ps1`, `GenericSqlQuery.ps1`, `Write-LogMessage.ps1`, `Get-FileChecksum.ps1`, `Get-RelativePath.ps1`; define no wrapper/module scope, process cache, assembly bootstrap, type declaration, feature operation, or discovery, so each consumer independently receives the eight functions.
- [X] T008 [P] [US1] Replace the duplicate shared-file dot-sources in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` with a direct dot-source of `../shared/Load.ps1`; retain its literal parameter/metadata/namespace declarations, explicit `Get-DelayIntervalInSecond.ps1` and `Compare-Column.ps1` selections, seven local functions, existing classes/method bodies, and empty helper exports.
- [X] T009 [P] [US1] Integrate the shared loader in `Fast1data.SqlServer/Fast1data.SqlServer.psm1`: declare `using module ./private/shared/GenericSqlParam.psm1`, keep bootstrap helper loading and `Import-SqlClientLib` visibly first at runtime, then dot-source shared Load and explicitly select `audit/Get-ImportState.ps1`, `audit/Get-SqlAuditFile.ps1`, `audit/Get-SqlAuditFileEntry.ps1`, `audit/Import-SqlAuditFile.ps1`, `migration/Get-Executed.ps1`, `migration/Set-Executed.ps1`, `migration/Resolve-MigrationPhase.ps1`, `migration/Invoke-Migration.ps1`, and `archiving/Invoke-ArchivingProcess.ps1`; remove private recursive discovery and its exclusion list, preserve public loading/exports, and enforce "Bootstrap/type dependencies stay distinct from shared behavior list". US2 will move the adapter's existing model declaration to the staged declaration loader.
- [X] T010 [US1] Run the US1 cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and a fresh L1/ARM worker via `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1`; record expected/discovered counts, ownership, two shared executions, and failures/skips in `specs/005-explicit-module-loaders/validation.md`, confirming the ownership-only fixture edit retains 136 inner cases.

**Checkpoint**: US1's shared-list contract passes without duplicate consumer lists or accidental reexecution through discovery. This is the first reviewable maintenance increment; hidden dependency directives and negative initialization acceptance are completed in US2.

---

## Phase 4: User Story 2 — Understand loading from explicit entry points (Priority: P1)

**Goal**: Designated loaders assemble every required dependency, bootstrap before typed feature loading, ignore unlisted files, and terminate incomplete initialization with useful context.

**Independent Test**: Run the US2 focused suite in fresh processes against disposable distributions. Account for all 21 original private files plus two new loaders, trace bootstrap-before-behavior, construct typed dependencies, leave a nested sentinel inactive, and inject missing/corrupt dependencies. Failures must terminate loading with original context, no usable public operation, and unchanged caller preferences.

### Tests for User Story 2

- [X] T011 [US2] Add inventory and AST assertions in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` for every intended private dependency, explicit root/model ownership, the declaration-only archiving loader, and absence of ordinary-file dependency directives; classify Kind as "Bootstrap, type declaration, shared behavior, component behavior" and OwningLoader as "Root, model, shared Load, or archiving declaration Load", enforcing "No recursive private-file enumeration, exclusions, or caller working-directory dependence" and "Ordinary behavior files perform no dependency assembly"; include an unlisted nested private script that would create a marker/throw if executed, and import from an unrelated working directory.
- [X] T012 [US2] Add cold direct-root and separate manifest-import cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, using T003 instrumentation in disposable copies to prove "SqlClient initialization completes before shared/feature runtime assembly"; verify bundled assembly provenance for the cold direct-root path, staged model declaration before adapter loading, supported bootstrapped model-first loading, and compatible already-loaded assembly reuse without assuming manifest-required SqlServer leaves the process cold.
- [X] T013 [US2] Add parameterized disposable-copy failure cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` for each selected shared behavior file, shared Load, archiving declaration Load, GenericSqlParam/Metadata/ArchivingModel modules, and missing/corrupt bundled SqlClient; enforce "All selected dependencies are required", "Failure terminates affected loading with safe path/stage context", and "Export operations only after required initialization succeeds"; capture useful original errors, verify no affected operation can proceed, and preserve caller error/verbose/warning preferences on success and failure without preloading assemblies in cold fault workers.

### Implementation for User Story 2

- [X] T014 [P] [US2] Add `Fast1data.SqlServer/private/archiving/Load.ps1` containing only literal `using module ./ArchivingModel.psm1` and comments explaining post-bootstrap declaration staging; add no executable behavior, functions, classes, exports, dynamic evaluation, or new module scope.
- [X] T015 [P] [US2] Remove the GenericSqlParam using declaration from `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1` and remove the parameter declaration and query dot-source from `Fast1data.SqlServer/private/migration/Set-Executed.ps1`; preserve their behavior bodies and typed parameter construction, relying on root/model declarations and the shared loader.
- [X] T016 [P] [US2] Remove the Metadata using declaration from `Fast1data.SqlServer/private/archiving/Compare-Column.ps1`; preserve comparison behavior and typed metadata usage, relying on the declaration in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`.
- [X] T017 [P] [US2] Remove the ArchivingModel using declaration from `Fast1data.SqlServer/private/archiving/Invoke-ArchivingProcess.ps1`; preserve `[TableGroup]::new(...)`, execution dispatch, logging, and error behavior, relying on the staged declaration supplied by root.
- [X] T018 [US2] Complete `Fast1data.SqlServer/Fast1data.SqlServer.psm1` staging by dot-sourcing `private/archiving/Load.ps1` after bootstrap and audit/migration assembly but before the adapter; make required bootstrap/script failures terminate with safe dependency/stage context and useful original details, restore any temporarily strengthened consumer error preference in `finally`, and expose public operations only after successful initialization; retain process-idempotent bootstrap and unchanged public discovery/export semantics.
- [X] T019 [US2] Complete terminating required-load handling in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1` around shared/helper assembly, preserving parser/type-module error context and restoring any temporarily changed preference in `finally`; keep shared definitions in the model's own scope, avoid child-scope wrappers, and retain all class/function bodies and empty exports.
- [X] T020 [US2] Run US1 and US2 focused cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, reconcile the 23-file post-change inventory with `specs/005-explicit-module-loaders/research.md`, and record cold traces, unrelated-directory/sentinel results, every required-dependency failure, class availability, error context, and preference preservation in `specs/005-explicit-module-loaders/validation.md`.

**Checkpoint**: All required dependencies are visibly selected by their owners; ordinary behavior files perform no loading. Unlisted files remain inactive and failed initialization cannot be used as a successful module.

---

## Phase 5: User Story 3 — Keep existing operations reliable (Priority: P2)

**Goal**: Preserve the public, class, logging, SQL, cleanup, progress, and retry contracts in source and packaged distributions and supported loading orders.

**Independent Test**: Run controlled suites, all 30 loading/order tuples per distribution, retained audit verbose coverage, relevant live SQL suites, and cold import/loader tests independently for source and package. Compare fixed public metadata and normalized observations, assert selected-distribution provenance, and account for every case and permitted skip. Record unavailable environments separately from passes.

### Tests and compatibility preparation for User Story 3

- [X] T021 [P] [US3] Extend `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Classes.ps1` within its existing class-fixture case with a real metadata-typed `Compare-Column` invocation through its owning model and parameter descriptor checks needed after directive removal, while retaining literal imports of all seven types, existing properties/constructors, both `TableGroup.Execute` overloads and the single-use guard; enforce "Available before typed behavior is used; no changed-class hot reload requirement" and the unchanged descriptor contract: "Existing validation and parameter binding remain unchanged."
- [X] T022 [P] [US3] Verify and maintain completeness assertions in `Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1` and `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`: retain L1–L5 crossed with ARM/AMR/RAM/RMA/MAR/MRA, one structured record per worker, 30 unique tuples, exact discovered-case accounting, and only the existing documented filesystem skip; retain 136 inner cases unless contained case counts change, updating both worker and driver together if they do; preserve `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json` as the fixed baseline enforcing "Three root commands; zero model helper commands" and leave new cold/fault cases outside this prebootstrapped matrix.

### Verification and integration for User Story 3

- [X] T023 [US3] Run controlled source suites in fresh processes using `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`, `Fast1data.SqlServer/tests/Audit.Common.Tests.ps1`, `Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1`, `Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Tests.ps1`, `Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1`, and applicable `Fast1data.SqlServer/tests/Audit.Windows.Tests.ps1` or `Fast1data.SqlServer/tests/Audit.Linux.Tests.ps1`; exclude integration filenames before discovery, retain real loggers and preference combinations, require all 30 source tuples and exactly one adverse-import audit "No audit files found" verbose message, and record expected/discovered cases and all outcomes in `specs/005-explicit-module-loaders/validation.md`.
- [X] T024 [US3] Review local fixture configuration and run `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1` in a fresh process against an explicitly selected disposable SQL database with documented permissions; verify ordered execution, checksums, force/ignore/path/duplicate validation, unchanged `-WhatIf` effects/history, SQL failure termination, history-write failure and idempotent retry using live and retained controlled coverage; record fixture selection, teardown, and actual outcomes or missing prerequisites in `specs/005-explicit-module-loaders/validation.md` without secrets.
- [X] T025 [US3] Review local fixtures and run the applicable `Fast1data.SqlServer/tests/Audit.Integration.Windows.Tests.ps1` or `Fast1data.SqlServer/tests/Audit.Integration.Linux.Tests.ps1` in a fresh process with an explicitly selected disposable SQL database and closed immutable audit files; verify imported/ignored offsets, resumed durable progress after lost responses, connection cleanup, and discovery requirements including Linux SMB prerequisites; record actual results, teardown, and unavailable host/resources in `specs/005-explicit-module-loaders/validation.md`.
- [X] T026 [US3] Review local fixture databases/permissions and run `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` in a fresh process; verify source/configuration-instance and primary-key constraints, archive/purge order, working sets, checkpoints, retries after committed writes or lost responses, FK restoration, and primary/cleanup errors without changing workflow or SQL bodies; record selected disposable databases, teardown, actual results, and missing prerequisites in `specs/005-explicit-module-loaders/validation.md`.
- [X] T027 [US3] Run `Invoke-ScriptAnalyzer` on every new/modified `.ps1`, `.psm1`, and `.psd1` file, including `Fast1data.SqlServer/Fast1data.SqlServer.psm1`, both `Load.ps1` scripts, modified behavior/model files, and test workers/fixtures; initialize types first, use repository settings if available, resolve all new errors/warnings without suppression or extending `out/publish.ps1`'s existing type filter, check AGENTS.md multiline/tab formatting, and record analyzed paths, pre-existing findings, or unavailable analysis in `specs/005-explicit-module-loaders/validation.md`.
- [X] T028 [US3] Execute the actual local staging/validation path `out/publish.ps1` after source checks and configured SQL prerequisites; verify `out/Fast1data.SqlServer/private/shared/Load.ps1`, `out/Fast1data.SqlServer/private/archiving/Load.ps1`, tests/fixtures, manifest, and all three runtime asset directories are included; change `out/publish.ps1` only if a concrete packaging omission is found, then analyze the modified script and rerun affected checks; record the full package gate result in `specs/005-explicit-module-loaders/validation.md` without gallery publication or treating staging after failure as a validated package.
- [X] T029 [US3] Repeat cold direct/manifest imports, focused loader cases, controlled suites, all 30 loading/order tuples, and applicable configured SQL suites in independent processes using only `out/Fast1data.SqlServer/` module/test/worker paths; compare the fixed public metadata and normalized source/package outcomes, assert private function/module/class and cold bundled assembly provenance beneath the selected package root, and record parity plus expected/discovered counts in `specs/005-explicit-module-loaders/validation.md`; do not fall back to source files or conceal an incomplete T028 package gate.
- [ ] T030 [US3] Validate source/package imports, focused coverage, applicable controlled suites/matrices, and runtime assets on available x64 Windows, Linux, and macOS hosts per `specs/005-explicit-module-loaders/quickstart.md`; record each host/runtime and pass/fail/skip/unavailable status in `specs/005-explicit-module-loaders/validation.md`, retaining audit discovery's Windows/Linux restriction and leaving unavailable host/SQL/package acceptance explicitly unverified.

**Checkpoint**: Existing public metadata and operational results remain compatible for every executed acceptance case. All expected cases are accounted for; unavailable prerequisites are visible and do not count as passing acceptance. Unresolved material integrity risks block release.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Document the final loader contract and make acceptance evidence reviewable.

- [X] T031 [P] Add concise maintainer guidance to `README.md` identifying `Fast1data.SqlServer/private/shared/Load.ps1` as the only shared list, root/model ownership, bootstrap-before-archiving-declaration order, behavior-only function files, unchanged three-command/runtime/configuration contracts, supported model-first prerequisites, and fresh-process recovery after repairing a required dependency.
- [X] T032 [P] Update `specs/005-explicit-module-loaders/quickstart.md` to match implemented test/worker paths, story tags, actual case accounting, cold fault-isolation commands, and source/package verification commands; retain disposable SQL fixture permissions, analyzer requirements, platform restrictions, and the distinction between staged output and a validated package.
- [X] T033 Reconcile `specs/005-explicit-module-loaders/validation.md` with every FR/SC and `specs/005-explicit-module-loaders/contracts/loader-boundaries.md`, recording final private inventory, one shared list/eight functions/two executions, no hidden loading, exact exports/metadata, negative cases, matrix totals, analyzer coverage, source/package parity, live SQL and per-host observations; review the final diff for preserved existing edits and unchanged SQL/workflow/public contracts, rerun only checks affected by any subsequent script changes, and identify outstanding acceptance gates without claiming them passed.

---

## Dependencies & Execution Order

### Phase dependencies

1. Setup T001–T002 establishes the baseline and prerequisites.
2. Foundation T003–T004 establishes the worker protocol and harness; it blocks every story.
3. US1 T005–T010 delivers the single shared list and integrates both consumers. Tests T005–T006 precede implementation; T007 precedes T008–T009; both entry-point changes precede T010.
4. US2 T011–T020 depends on US1's loader integration. Add tests T011–T013 first. T014–T017 can then proceed independently; T018 depends on their completion. T019 follows T018 in the default execution order, and T020 follows both loader error-handling tasks.
5. US3 T021–T030 integrates completed US1 and US2. T021–T022 prepare compatibility checks before T023. Run T024–T026 sequentially unless separate disposable database fixtures are explicitly configured; they may otherwise share instance/database state. T027 follows source changes. T028 requires source acceptance and configured live prerequisites; T029 requires a successfully validated package. T030 extends verification to available hosts.
6. Polish T031–T033 follows the story checks. T031–T032 can overlap; T033 reconciles their final state and all evidence.

### User story completion graph

```text
Setup → Foundation → US1 (P1, shared-list MVP)
                         ↓
                     US2 (P1, complete explicit/failure boundaries)
                         ↓
                     US3 (P2, operational/source/package acceptance)
                         ↓
                       Polish
```

US1 includes root's explicit file selection because retaining discovery would load the new shared script accidentally and invalidate US1's two-execution test. US2 owns complete declaration staging, ordinary-file cleanup, inventory/sentinel acceptance, and failure handling. This dependency is deliberate; US2 and US3 are independently testable checkpoints after their prerequisites, not parallel standalone deliveries.

### Within each story

- Add new acceptance assertions before corresponding implementation and observe the intended pre-change failure. Do not weaken fixed metadata, real logging, cleanup, or durable-state expectations to pass loading changes.
- Apply literal type declarations before typed behavior is parsed/used; bootstrap SqlClient before compiling model types. Runtime `Import-Module` alone is not a substitute for the required class declaration boundary.
- Keep direct consumer dot-sourcing; do not introduce a third shared service module, factories, global type accelerators, dynamic script evaluation, or wrapper scopes.
- Use portable loader-relative paths and AGENTS.md tab-indented multiline PowerShell control-flow blocks. Do not add `.vscode/` to `.gitignore`.
- Do not mark an implementation task complete until applicable analyzer and affected verification results are recorded. Record unrelated baseline findings separately. Missing tools/hosts/SQL fixtures leave corresponding validation tasks incomplete rather than passing by omission.

### Parallel opportunities

- Twelve tasks carry `[P]` markers across five independent-file waves: T005/T006, T008/T009, T014/T015/T016/T017, T021/T022, and T031/T032.
- T003's worker, T004's harness, and successive changes to `ModuleLoaders.Tests.ps1` are sequential because later work depends on their protocol/content.
- Source/package and host test processes can overlap only when their distribution copies, result destinations, and database fixtures are isolated. Keep the evidence-file writer serialized.

## Parallel Example: User Story 1

After Foundation, add the two independent test changes together:

```text
T005: Shared-list contract tests in Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1
T006: Ownership expectations in Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1
```

After T007 creates shared Load, integrate the two different entry files together:

```text
T008: Model integration in Fast1data.SqlServer/private/archiving/ArchivingModel.psm1
T009: Root integration in Fast1data.SqlServer/Fast1data.SqlServer.psm1
```

Run T010 only when both consumers are integrated.

## Parallel Example: User Story 2

After US1 and the US2 test additions T011–T013:

```text
T014: Declaration-only Fast1data.SqlServer/private/archiving/Load.ps1
T015: Directive removal in shared/GenericSqlQuery.ps1 and migration/Set-Executed.ps1
T016: Directive removal in archiving/Compare-Column.ps1
T017: Directive removal in archiving/Invoke-ArchivingProcess.ps1
```

These tasks touch different files. Complete root/model integration and error handling before running the acceptance checkpoint; partial directive removal is not a working delivery.

## Parallel Example: User Story 3

After US2:

```text
T021: Typed compatibility fixture in Fast1data.SqlServer/tests/fixtures/SharedHelpers.Classes.ps1
T022: Case accounting in Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1
      and Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1
```

Run the source matrix after both edits. Do not parallelize live SQL suites sharing fixture databases or validate the package in a source-preloaded session.

## Implementation Strategy

### MVP first

Complete Setup, Foundation, and US1, then use T010 to review the single-list maintenance improvement in isolation. US1's explicit root selection prevents discovery from executing shared Load again. This MVP is a review checkpoint, not a claim that full feature acceptance, negative loading behavior, or packaging has passed.

### Incremental delivery

1. US1 establishes the list and private ownership in both consumers.
2. US2 finishes language-required declaration staging, behavior-only files, fail-fast initialization, and cold/sentinel/fault acceptance without changing constructors or workflow bodies.
3. US3 proves existing operation contracts and source/package parity using the retained matrix, live SQL where required, and available supported hosts.
4. Polish documents the final assembly responsibilities and reconciles evidence. Preserve configuration, schemas, persisted progress, retry behavior, runtime assets, and public metadata throughout.

### Completion accounting

There are **33 tasks**: Setup **2**, Foundation **2**, US1 **6**, US2 **10**, US3 **10**, and Polish **3**. **12 tasks** are marked `[P]`. Unavailable checks remain documented outstanding gates; a directory produced by failed packaging or a partially discovered matrix does not satisfy acceptance.
