---
description: "Executable tasks for removing macOS x64 support"
---

# Tasks: Drop macOS x64 Support

**Input**: Design documents from `specs/008-drop-osx-x64/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [runtime support contract](contracts/runtime-support.md), [quickstart.md](quickstart.md), and the active `.specify/memory/constitution.md`.

**Tests**: The specification explicitly requests packaging, platform rejection, supported-entry-point, and existing command acceptance scenarios (US1–US2, SC-001–SC-003). Add focused behavioral Pester coverage and reuse existing command suites. Write new regression assertions first and establish the relevant failures before changing production behavior. Documentation acceptance is a consistency review, without redundant prose tests.

**Organization**: Tasks are grouped by user story and describe the implementation work from the design; generating this file does not implement or validate the feature. Stay on the existing `dev` branch. Do not publish a release during validation.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies tasks that can run concurrently after their stated prerequisites, in different files.
- `[US1]`, `[US2]`, and `[US3]` map to the specification's stories.
- All paths are relative to the repository root, except generated paths explicitly relative to a disposable checkout.
- Use tab-indented, multiline PowerShell blocks with opening braces on the statement line. Preserve `.vscode/` tracking.

## Path Conventions

- Production: `build/build.ps1`, `out/publish.ps1`, and `Fast1data.SqlServer/`.
- Tests: `Fast1data.SqlServer/tests/`; test-only workers: `Fast1data.SqlServer/tests/fixtures/`.
- Generated bundles: `Fast1data.SqlServer/lib/<rid>`; generated stage: `out/Fast1data.SqlServer/`.
- Execution evidence: `specs/008-drop-osx-x64/validation.md`, created during implementation. Include commands, actual versions, host OS/architectures, source/stage provenance, pass/fail/skip counts, and unavailable prerequisites. Never record secrets.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish prerequisites and an evidence destination without adding project dependencies.

- [X] T001 Verify PowerShell 7.6+ Core, reported OS/process X64 on the current retained host, a .NET SDK supporting `net10.0`, Pester 6+, PSScriptAnalyzer and available repository analyzer settings; inventory native Windows/Linux and explicitly configured SQL test availability using `specs/008-drop-osx-x64/quickstart.md`, and create `specs/008-drop-osx-x64/validation.md` with actual prerequisites and all acceptance checks initially unrun. Do not print connection strings or credentials or treat missing environments as passes.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the existing contracts that every story must preserve. No new production policy module, database model, public platform override, or dependency is needed.

- [X] T002 Capture the pre-change contract baseline in `specs/008-drop-osx-x64/validation.md`: inspect `Fast1data.SqlServer/Fast1data.SqlServer.psd1`, `Fast1data.SqlServer/Fast1data.SqlServer.psm1`, `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json`, `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and `build/SqlClientLoader.csproj`; record the six exports, unchanged command snapshot, 23-file private inventory, loader/model-bootstrap order, parameterless resolver, PowerShell baseline and current dependency versions, and run existing loader/shared-helper suites on the current supported host when assets are available. Record baseline failures or missing assets without changing snapshots, counts, or skip rules.

**Checkpoint**: Prerequisites and preserved contracts are recorded. All stories may start after T002; native release acceptance remains a final gate.

## Phase 3: User Story 1 — Obtain a release for the supported platforms (Priority: P1) — MVP

**Goal**: Build and stage exactly the two retained bundles while preserving dependencies and public command behavior.

**Independent Test**: In isolated clean and reused roots, run build/staging acceptance and verify exactly `win-x64` and `linux-x64`, both managed DLLs, native/resource assets, and exclusion of stale macOS assets. On each retained native host, both root entry points and the model/shared-helper paths must retain existing command acceptance; final source/stage and SQL evidence is collected by T019–T023.

### Tests for User Story 1

- [X] T003 [P] [US1] Add `Fast1data.SqlServer/tests/fixtures/Invoke-PackagingScenario.ps1` to run the actual `build/build.ps1` and `out/publish.ps1` from marked disposable repository roots in fresh processes; copy only required source inputs, control external `dotnet publish` results/assets when appropriate, seed obsolete/source/stage markers and native/resource files, and emit structured observations of publish RIDs, output paths, failures and retained sentinels. Validate absolute fixture destinations before cleanup; never rebuild or delete the developer's real bundles. Preserve actual production cleanup/copy/preflight logic, and report source-only scenarios unavailable in staged distributions without silently claiming coverage.
- [X] T004 [US1] Add `Fast1data.SqlServer/tests/Packaging.Tests.ps1` using T003: cover clean/reused builds, exactly two publish calls, stale macOS source removal, standalone staging with stale macOS source and stage, nested `publish` exclusion, both DLLs and native/resource content preservation, nonzero publish/copy failures, missing published/copied/staged assets, and unexpected source/staged RID rejection. Exercise unsafe cleanup destinations only inside validated disposable roots, assert outside sentinels survive, and assert missing-source preflight preserves the previous stage. Inject faults into disposable copies with checked substitutions or scoped test interception, keeping the exercised guard/assertion logic intact. Run the suite and record the relevant pre-implementation failures in `specs/008-drop-osx-x64/validation.md`; dependencies: T003.

### Implementation for User Story 1

- [X] T005 [P] [US1] Restrict `build/build.ps1` to `win-x64` and `linux-x64`; before publishing, resolve and validate the exact absolute parent/basename of `Fast1data.SqlServer/lib/osx-x64` and remove only that obsolete source directory if present. Preserve supported destination guards, required DLL checks and per-target failure handling; assert the exact source RID directory set after publishing, failing on unexpected directories instead of deleting them. Enforce bundle constraints verbatim: "Exactly one retained RID per bundle directory.", "Destination absolute parent and basename validated before recursive cleanup.", "Both exist after publishing/copying; runtime retains identity/type validation.", and "Retained intact for supported targets; no dependency version changes." Keep `build/SqlClientLoader.csproj`, build caches and user installations unchanged; dependency: T004.
- [X] T006 [P] [US1] Restrict the allowlist in `out/publish.ps1` to two targets and assert the exact staged RID directory set after copying. Preserve required-source preflight before stage deletion, validated stage recreation, allowlisted copies, nested-publish exclusion, manifest/import/analyzer checks and terminating failures; staging must exclude stale macOS source assets without requiring a rebuild. Enforce release fields "Existing `out/Fast1data.SqlServer`" and "Exactly `{win-x64, linux-x64}`"; retain "Current module source, selected documentation and required libraries". `-StageOnly` must neither run Pester nor publish to a gallery; dependency: T004.
- [X] T007 [P] [US1] Update only runtime-asset assertions in `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1` to require the exact directory set `win-x64` and `linux-x64`, rejecting extra directories rather than merely checking presence. Preserve `Fast1data.SqlServer/tests/fixtures/SharedHelpers.PublicContract.json`, all command metadata, ownership assertions and the five-loading-pattern by six-operation-order matrix; dependency: T004.
- [X] T008 [US1] Run `Fast1data.SqlServer/tests/Packaging.Tests.ps1`, `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` and `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1` against the updated source on the current retained host, using the existing `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1` Manifest, Direct and ModelFirst workers in fresh processes. Verify six exports, factory behavior, assembly provenance, frozen signatures/ownership and preserved shared/model loading; record results in `specs/008-drop-osx-x64/validation.md`. Do not confuse controlled publishing with real build or native Linux acceptance; dependencies: T005–T007.

**Checkpoint**: Packaging behavior passes focused acceptance and supported-host imports retain their contracts. US1 is the first implementation increment; release completion still requires both P1 stories, US3 and the final gates.

## Phase 4: User Story 2 — Receive a clear unsupported-platform result (Priority: P1)

**Goal**: Reject macOS and every unsupported reported OS/architecture combination before bundle lookup or operational initialization, even with old assets or preloaded assemblies.

**Independent Test**: A native-fact matrix returns only the two matching retained RIDs. Fresh-process `.psd1` and `.psm1` imports under simulated unsupported facts terminate with the reason and both supported alternatives, with zero bundle access, later bootstrap/behavior loading or database attempts. Valid leftover assets and compatible preloads cannot bypass rejection. Supported-host dependency failures retain their existing diagnostics.

### Tests for User Story 2

- [X] T009 [P] [US2] Add `Fast1data.SqlServer/tests/fixtures/Invoke-RuntimeSupportScenario.ps1` to exercise the real selector and root imports in fresh processes against marked disposable distribution copies. Substitute only native OS-flag and RuntimeInformation OS/process-architecture expressions with controlled literals, validate every intended substitution count, and leave selector/error/loading logic intact. Add test-local probes for bundle lookup, required-library reuse/loading, later operational loading and database attempts; preload valid compatible assemblies before enabling those probes where required. Report facts, entry point, error and probe counts; refuse mutation without a validated copy marker and never force global host OS variables or mock the resolver to throw.
- [X] T010 [US2] Add selector matrix assertions in `Fast1data.SqlServer/tests/RuntimeSupport.Tests.ps1` using T009 for both accepted X64/X64 targets, macOS X64/ARM64, unknown OS, Windows/Linux reported ARM64/X86 including an X64 process, and X64 OS with non-X64 processes; enumerate non-X64 architecture enum values where available. Assert exact RIDs or terminating rejection with both supported alternatives and no fallback; record pre-change failures in `specs/008-drop-osx-x64/validation.md`; dependency: T009.
- [X] T011 [US2] Extend `Fast1data.SqlServer/tests/RuntimeSupport.Tests.ps1` with fresh-process rejection imports through both `Fast1data.SqlServer.psd1` and `Fast1data.SqlServer.psm1`, covering unsupported facts and the macOS X64/ARM64 × stale-bundle absent/present × cold/compatible-preload matrix. Include valid library files in leftover directories, assert zero bundle lookup/reuse/loading, later operational imports and database attempts, and require both alternatives without a missing-macOS-DLL or macOS-rebuild diagnosis. Establish the relevant pre-change failures in `specs/008-drop-osx-x64/validation.md`; dependency: T010.

### Implementation for User Story 2

- [X] T012 [US2] Update only the existing parameterless resolver in `Fast1data.SqlServer/private/shared/Get-RuntimeIdentifier.ps1`: accept operating system "Windows or Linux" with "macOS and all other systems reject before dependency lookup."; require reported OS architecture "`Architecture.X64`" with "Other reported values reject; retain existing OS-architecture restriction." and process architecture "`Architecture.X64`" with "A non-x64 process cannot select an x64 bundle."; return only "`win-x64` or `linux-x64`" with "Derived only from valid native facts; no fallback." Reject unsupported OS before architecture/bundle selection and name x64 Windows (`win-x64`) and x64 Linux (`linux-x64`) in every rejection. Preserve the resolver's position before the dependency wrapper in `Fast1data.SqlServer/private/shared/Import-RequiredLibrary.ps1` and the root bootstrap order; dependencies: T010–T011.
- [X] T013 [US2] Run the existing supported-host missing/corrupt/type/preload fault cases in `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1` using `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1`; verify DLL name, selected RID, expected path, `build/build.ps1` rebuild guidance, fresh-process recovery and underlying failure remain distinguishable from platform rejection. Record evidence in `specs/008-drop-osx-x64/validation.md`; add assertions to those test files only if a required diagnostic is currently unasserted, without changing production loader contracts; dependency: T012.
- [X] T014 [US2] Run all cases in `Fast1data.SqlServer/tests/RuntimeSupport.Tests.ps1` and confirm matching retained targets and rejection probe counts; record pass/fail/skip counts in `specs/008-drop-osx-x64/validation.md`, explicitly labeling substituted facts as simulation. Verify no new production file, private inventory entry, public parameter or emulation/physical-host detection was introduced; dependencies: T012–T013.

**Checkpoint**: Unsupported platforms cannot reach dependency lookup or operational initialization. Supported dependency diagnostics remain actionable.

## Phase 5: User Story 3 — Understand the compatibility change before upgrading (Priority: P2)

**Goal**: Publish consistent current platform statements, a module version decision and the authorized compatibility amendment with usable host-transition guidance.

**Independent Test**: Review manifest version/tags/release notes, README installation and upgrade guidance, current help/guides and constitution together. All advertise exactly x64 Windows/Linux, explicitly remove macOS in this release and explain moving execution while preserving state/configuration. Module 0.2.0 and constitution 2.0.0 are independently recorded; historical records remain intact.

### Implementation for User Story 3

- [X] T015 [P] [US3] Update `Fast1data.SqlServer/Fast1data.SqlServer.psd1` to module version "Planned `0.2.0`" and metadata "Windows/Linux tags and immediate macOS-removal release guidance" from `specs/008-drop-osx-x64/data-model.md` (adopting the planned version). Release notes must state immediate macOS removal, unsupported ARM64/other platforms, and moving execution to x64 Windows or Linux. Preserve "Existing six commands, signatures and manifest exports", PowerShell 7.6+ Core and dependency baselines; preserve earlier release history if present.
- [X] T016 [P] [US3] Update requirements, bundled RID list and upgrade guidance in `README.md` to exactly x64 Windows/Linux and immediate macOS removal in module 0.2.0. Explain moving orchestration to a retained host while preserving database state, migration history/checksums and portable paths, audit checkpoints, archiving state and configuration; arrange equivalent external file/share access, permissions and credentials, with no database-format migration. State unsupported ARM64/other platforms and unchanged PowerShell/dependency prerequisites without exposing secrets.
- [X] T017 [P] [US3] Adopt the already-authorized constitution 2.0.0 amendment in `.specify/memory/constitution.md`: replace Principle IV's opening sentence exactly with "The module MUST maintain its documented PowerShell 7.6-or-later Core baseline and x64 Windows and Linux support until an explicit compatibility change is approved." Add the rationale, approved macOS removal, affected build/loading/metadata contracts, module 0.2.0 decision and retained-host transition from `specs/008-drop-osx-x64/research.md`; preserve the original ratification field and Amendment 1.1.0 and set the last-amended date to the actual adoption date. Authorization is recorded in the specification; no new compatibility approval is needed.
- [X] T018 [US3] Review current support/help statements in `Fast1Audit.md`, `Fast1Migration.md`, `Fast1Archiving.md` and all six files under `Fast1data.SqlServer/public/` (`Invoke-Fast1Audit.ps1`, `Invoke-Fast1Migration.ps1`, `Invoke-Fast1Archiving.ps1`, `Invoke-Fast1GenericSqlQuery.ps1`, `Invoke-Fast1GenericSqlQueryReader.ps1`, `New-Fast1GenericSqlParam.ps1`); correct any conflicting current macOS support promises without changing command behavior/signatures or historical specs/releases, and record reviewed paths and any edits in `specs/008-drop-osx-x64/validation.md`; dependencies: T015–T017.

**Checkpoint**: Current installation, package and policy statements agree, and macOS users can plan the host transition without a database conversion.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate the integrated implementation and record release-readiness evidence. Each unavailable native host, analyzer or SQL environment leaves its gate unverified; do not mark that task complete as passing. Record the limitation and leave the acceptance work open for an environment that can run it.

- [X] T019 Execute the real `build/build.ps1` and `out/publish.ps1 -StageOnly` in a disposable checkout of the completed implementation, following clean, reused source/stage, and standalone-staging scenarios in `specs/008-drop-osx-x64/quickstart.md`. Assert exactly two source/staged RID directories after build/stage, both DLLs and retained native/resource file lists and SHA-256 hashes; reseed macOS fixtures to prove stage-only filtering, then rebuild to restore the exact source set before shared-helper acceptance. Record commands/results and final source/stage identities in `specs/008-drop-osx-x64/validation.md`; never publish to a gallery.
- [X] T020 On native Windows x64 with an x64 PowerShell process, run `Fast1data.SqlServer/tests/RuntimeSupport.Tests.ps1`, `Fast1data.SqlServer/tests/Packaging.Tests.ps1`, `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`, `Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1`, fresh Manifest/Direct/ModelFirst workers in `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1`, and remaining offline command suites discovered as in `specs/008-drop-osx-x64/quickstart.md`; repeat applicable suites/workers from `out/Fast1data.SqlServer/tests/`, explicitly identifying source-only packaging scenarios. Record distinct native Windows source/stage results and frozen six-command/ownership evidence in `specs/008-drop-osx-x64/validation.md`; dependency: T019.
- [X] T021 On native Linux x64 with an x64 PowerShell process, repeat the source/stage focused, import, shared-helper and offline acceptance from T020 using `Fast1data.SqlServer/tests/` and `out/Fast1data.SqlServer/tests/`; require correct native dependencies, both root entry points, model bootstrap, five-by-six matrix and six-command snapshot. Record native Linux results separately in `specs/008-drop-osx-x64/validation.md`; cross-published Linux files or simulated facts do not satisfy this gate; dependency: T019. Keep concurrent host logs separate and reconcile this evidence file sequentially.
- [X] T022 On native Windows x64, run `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`, `Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1`, `Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1` and `Fast1data.SqlServer/tests/Audit.Integration.Windows.Tests.ps1`, then their `out/Fast1data.SqlServer/tests/` counterparts, using only explicitly selected test resources and documented permissions/environment variables. Verify existing migration checksums/order/history/preview/retry, query values/ownership and audit/archiving progress acceptance; record actual non-skipped results in `specs/008-drop-osx-x64/validation.md`, without changing schema/configuration formats or exposing secrets; dependency: T020.
- [X] T023 On native Linux x64, repeat T022 using `Fast1data.SqlServer/tests/Audit.Integration.Linux.Tests.ps1` with the other three integration suites and their staged counterparts; satisfy documented SMB/file permissions where needed and record distinct native Linux source/stage results in `specs/008-drop-osx-x64/validation.md`. Missing SQL settings or skipped suites leave acceptance unverified; dependency: T021. Do not concurrently use the same mutable SQL fixtures as T022; reconcile the evidence file sequentially.
- [X] T024 Record native macOS rejection availability in `specs/008-drop-osx-x64/validation.md`; when a native host is available, perform cold imports of both `Fast1data.SqlServer/Fast1data.SqlServer.psd1` and `Fast1data.SqlServer/Fast1data.SqlServer.psm1` from disposable copies with and without valid leftover macOS libraries, and verify rejection naming both supported alternatives before database setup. If unavailable, explicitly record native macOS rejection as unrun and link the simulated T014 evidence instead; native macOS evidence is supplemental, not a substitute for the required Windows/Linux gates; dependency: T014.
- [X] T025 Run `Invoke-ScriptAnalyzer` with discovered repository settings on every changed/new `.ps1`, `.psm1` and `.psd1`, including `build/build.ps1`, `out/publish.ps1`, `Fast1data.SqlServer/private/shared/Get-RuntimeIdentifier.ps1`, manifest, tests/workers and any public help edits; verify package-wide analyzer/import success through real `out/publish.ps1 -StageOnly`. Resolve introduced warnings/errors without rule suppression; record command scope, unrelated baseline findings and unavailable tooling in `specs/008-drop-osx-x64/validation.md`. Re-run affected acceptance only if fixes change behavior or assets; dependencies: T018–T023.
- [X] T026 Complete the FR-001–FR-008 / SC-001–SC-004 evidence mapping in `specs/008-drop-osx-x64/validation.md` against `specs/008-drop-osx-x64/contracts/runtime-support.md`: confirm source/stage exact sets, both native retained-host command results, unsupported-platform zero-operation results, module 0.2.0, constitution 2.0.0 and consistent `README.md`/manifest/help/transition guidance. Preserve honest pass/fail/skip/unrun statuses and open release gates; do not certify release readiness from StageOnly alone. Review the final diff for unchanged database/state/configuration/public contracts and historical records; dependencies: T019–T025.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup (T001) -> Foundation (T002)
                         |-> US1 / packaging (T003-T008) --|
                         |-> US2 / rejection (T009-T014) -|-> Integrated validation (T019-T026)
                         |-> US3 / guidance (T015-T018) --|
```

- US1 and US2 are both P1. Execute US1 first for the suggested MVP, then US2; their source changes can also proceed independently after T002.
- US3 is P2 and has no implementation dependency on US1/US2, but all three stories must be integrated before final build/stage verification.
- Within US1: T003 → T004 → {T005, T006, T007} → T008.
- Within US2: T009 → T010 → T011 → T012 → T013 → T014. The matrix and import tests share one file and must be edited sequentially.
- Within US3: {T015, T016, T017} → T018.
- Final gates: T019 → {T020 → T022, T021 → T023}; T014 → T024; completed implementation/host gates → T025 → T026.
- Native host jobs may run concurrently using separate disposable checkouts and logs. SQL jobs require distinct explicitly selected resources or sequential execution. The shared `validation.md` is reconciled by one writer.

### Parallel Opportunities

- T003 and T009 build separate test-only fixtures after the common baseline.
- After T004's failures are established, T005 (build), T006 (stage) and T007 (shared-helper asset assertions) edit separate files.
- T015–T017 update three separate files and can proceed after T002, including alongside runtime/packaging work.
- US1 packaging tests and US2 runtime tests use separate suite/worker files. Preserve each story's internal prerequisites.
- T020/T021 and then T022/T023 can run on separate retained hosts when environment and SQL isolation allow; these are not marked `[P]` because their shared evidence updates and resources require coordination.

## Parallel Example: User Story 1

After T004 establishes failing regressions:

```text
T005: Restrict build targets, safely remove stale source assets and assert source RIDs — build/build.ps1
T006: Restrict staging allowlist and assert staged RIDs — out/publish.ps1
T007: Require exactly two runtime bundles — Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1
```

Join these tasks before T008. Do not run multiple destructive fixture scenarios against the same disposable root.

## Parallel Example: User Story 2

```text
After T002:
T009: Build disposable runtime fact/import worker — Fast1data.SqlServer/tests/fixtures/Invoke-RuntimeSupportScenario.ps1
T003 (US1): Build disposable packaging worker — Fast1data.SqlServer/tests/fixtures/Invoke-PackagingScenario.ps1
```

US2 has no safe internal file-edit parallelism after fixture creation: T010/T011 share `RuntimeSupport.Tests.ps1`, and T012 depends on their failing assertions. After the worker is ready, independent matrix cases can execute in separate child processes/copies with observations collected by one suite writer.

## Parallel Example: User Story 3

After T002:

```text
T015: Adopt module version, platform tags and release notes — Fast1data.SqlServer/Fast1data.SqlServer.psd1
T016: Update requirements and host-transition guidance — README.md
T017: Adopt the authorized compatibility amendment — .specify/memory/constitution.md
```

Join these before T018's current-help review and the final consistency check.

## Implementation Strategy

### MVP First (User Story 1)

1. Complete T001–T002, establish packaging failures, and implement T003–T008.
2. Demonstrate clean/reused packaging and retained-host loading as the first independently testable increment.
3. Complete US2 before distributing the compatibility change: removing files alone does not satisfy the unsupported-platform contract.
4. Complete US3 and integrated native/build/SQL/analyzer gates before release readiness is asserted.

### Incremental Delivery

1. US1 establishes two-target build/staging and preserved loader/command contracts.
2. US2 adds early rejection that cannot be bypassed by stale libraries or preloads.
3. US3 aligns version, metadata, policy and host-transition guidance.
4. Final validation establishes real clean/reused outputs, native Windows/Linux source/stage behavior and existing SQL acceptance, recording missing prerequisites as open work.

### Requirement Coverage

| Requirement | Primary implementation / validation tasks |
|---|---|
| FR-001: exactly two supported runtime targets | T005–T007, T010–T012, T019–T021 |
| FR-002 / SC-001: clean/reused two-bundle distributions | T003–T008, T019 |
| FR-003 / SC-003: macOS rejection before operations | T009–T014, T024 |
| FR-004: unsupported OS/architectures, no fallback | T010–T012, T014 |
| FR-005 / SC-002: retained imports, diagnostics and commands | T002, T007–T008, T013, T020–T023 |
| FR-006 / SC-004: consistent support statements and guidance | T015–T018, T026 |
| FR-007: compatibility amendment and version decision | T015, T017, T026 |
| FR-008: compatible database/history/configuration/behavior | T002, T016, T020–T023, T026 |
| Constitution verification and analyzer obligations | T001–T002, T019–T026 |

## Notes

- No new production abstraction, package upgrade, command parameter, schema migration or persistence representation is part of this feature.
- Native facts are best-effort RuntimeInformation reports; do not introduce physical-host or emulation detection.
- Use valid leftover assets/preloads in runtime rejection coverage, not only empty obsolete directories.
- Keep historical specs, old release records and users' existing installations intact.
- Mark tasks complete only after their stated outcome is established. Supplemental macOS availability reporting can complete with an explicit unavailable result; required native Windows/Linux and SQL acceptance cannot.
