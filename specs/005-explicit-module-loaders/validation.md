# Implementation validation: explicit module loaders

## Baseline and environment

- Revision: `3fa3aab9dea04c5118bd73fb54f8c12bd040b015`; branch: `dev`.
- Starting edits: root and ArchivingModel explicitly loaded GenericSqlCleanup; GenericSqlQuery's cleanup dot-source had already been removed. Preserve those changes through the consolidated shared loader.
- Windows x64, Windows 10.0.26300; PowerShell Core 7.6.9; Pester 6.2.0; PSScriptAnalyzer 1.25.0; SqlServer 22.4.5.1.
- All three bundled Microsoft.Data.SqlClient assemblies exist (win-x64, linux-x64, osx-x64; each 1,670,040 bytes). No dependency rebuild required. No repository analyzer settings found.
- Git ignore rules already cover build/bin, build/obj, runtime libraries, staged output, and temporary/editor artifacts. No other technology-specific ignore file is required. `.vscode/` remains available for tasks.
- Integration suites select `pester-srv` and generate disposable `fast1_*_test_*` databases. They require create/drop database and fixture-object permissions. Audit additionally requires closed, immutable nonempty files at its configured share. Fixture availability will be checked separately; no credentials belong in this report.
- Planning evidence only: disposable type/scope probes and four passing Audit.Common cases. These are not implementation acceptance results.

## Original private inventory (21 files)

| Kind / intended owner | Files beneath private/ |
|---|---|
| Bootstrap / root | shared/Get-RuntimeIdentifier.ps1; shared/Import-SqlClientLib.ps1 |
| Shared behavior / shared Load, independently root and model | shared/GenericSqlCleanup.ps1; shared/GenericSqlQuery.ps1; shared/Write-LogMessage.ps1; shared/Get-FileChecksum.ps1; shared/Get-RelativePath.ps1 |
| Type declaration / root and model | shared/GenericSqlParam.psm1 |
| Component behavior / root | audit/Get-ImportState.ps1; audit/Get-SqlAuditFile.ps1; audit/Get-SqlAuditFileEntry.ps1; audit/Import-SqlAuditFile.ps1; migration/Get-Executed.ps1; migration/Set-Executed.ps1; migration/Resolve-MigrationPhase.ps1; migration/Invoke-Migration.ps1; archiving/Invoke-ArchivingProcess.ps1 |
| Component behavior / model | archiving/Get-DelayIntervalInSecond.ps1; archiving/Compare-Column.ps1 |
| Type declaration / model | archiving/Metadata.psm1 |
| Model entry / archiving declaration Load | archiving/ArchivingModel.psm1 |

Add shared/Load.ps1 and archiving/Load.ps1 for a final inventory of 23 files. Model retains seven local functions and all existing classes.

## Evidence checklist

- [X] FR-001 / SC-001: single ordered five-file shared list.
- [X] FR-002: eight functions per consumer, two independent executions and defining session states.
- [X] FR-003 / SC-002: explicit root inventory, inactive nested sentinel, unrelated working directory.
- [X] FR-004: model-only helpers and local functions.
- [X] FR-005: behavior-only files, descriptor/metadata/class availability.
- [X] FR-006: cold bundled bootstrap before behavior; manifest and compatible reuse independently tested.
- [X] FR-007: required dependency failures, original context, no usable operations, caller preferences preserved.
- [X] FR-008 / SC-003: fixed metadata, three exports, literal classes, source/package matrices (Windows; other hosts unverified).
- [X] FR-009: logging, SQL/cleanup, workflows, progress/retries and live SQL (Windows).
- [ ] SC-004: complete source/package acceptance and host accounting.

## Execution results

### Setup, foundation, and US1 (T001–T010)

Prerequisites and the 16/16 requirements checklist passed. The worker/harness uses absolute distribution roots, fresh pwsh -NoLogo -NoProfile processes, structured completion/exit checks, unrelated working directories, and marked disposable copies for mutation. Cold direct imports do not preload SqlServer or SqlClient.

Before implementation, shared-list assertions failed because Load.ps1 was absent and the model lacked checksum/path helpers. Updating the retained ownership case exposed that same pre-change defect among all 136 discovered inner cases. After integration, the initial five focused tests passed; L1/ARM discovered 136, passed 135, failed 0, skipped 1 (the existing case-sensitive-filesystem case). An initially overstrict absence assertion resolved a globally bootstrapped helper inherited from the worker; the corrected assertion rejects ownership by the model, retaining module/session-state identity and selected-path checks.

The shared loader literally selects cleanup, query, logging, checksum, and relative-path files in that order. Both consumers independently own all eight functions. Instrumented root-first and explicitly bootstrapped model-first imports each execute shared Load exactly twice in distinct scopes, emit no initialization output, and preserve root definitions after model import. Extending only a disposable shared list adds the new helper to both consumers.

### Explicit boundaries and failures (T011–T020)

The pre-change US2 run discovered 42 selected cases: 4 passed and 38 failed, exposing hidden using/dot-source directives, missing staging, and incomplete-load continuation. The implemented focused suite discovers **47 cases**, with **47 passed, 0 failed, 0 skipped**: four US1, 42 US2, one US3 harness case. The 42 US2 cases include 37 fault cases and five structure/success cases.

The final 23-file inventory is exactly the 21-file table above plus shared/Load.ps1 and archiving/Load.ps1. AST checks reconcile every dependency with its owning loader, prohibit private recursion/exclusions and ordinary-file assembly, and require the archiving staging script to contain only the literal model declaration. A nested throwing sentinel remains inactive. All imports run from an unrelated directory.

Root declares GenericSqlParam, bootstraps SqlClient, loads shared/audit/migration behavior, dot-sources the model declaration, then loads the adapter and public commands. Model retains literal parameter/metadata/namespace declarations, shared Load, two explicit archiving helpers, seven local functions, original class bodies, and empty helper exports. The class fixture exercises all seven literal types, a real metadata-typed comparison (matching and incompatible columns), descriptor construction in both consumers, both Execute overloads, and the single-use guard without increasing its contained test count.

Fault cases cover all 23 selected private dependencies and the host SqlClient DLL, corrupt script/type/assembly dependencies, direct model failures, and nonterminating Write-Error inside a required shared script. Every case rejects initialization, leaves no affected operation usable, and preserves caller ErrorActionPreference/VerbosePreference/WarningPreference. Runtime failures retain dependency stage, script stack, and inner exception. PowerShell declaration errors can reject Import-Module before loader runtime without throwing to a Continue caller; the worker captures those original errors and requires absent operations/modules. Metadata compiler failures can identify ArchivingModel.psm1 and unresolved TableColumn/IndexColumn instead of repeating Metadata.psm1; that original compiler context is preserved and verified.

Cold direct-root imports use the selected distribution's bundled assembly. Manifest imports are separate and legitimately may reuse SqlServer's assembly. Explicit preload followed by renaming the bundled DLL verifies compatible process reuse. Disposable instrumentation confirms bootstrap before shared behavior and the adapter, and declarations before adapter loading. A subsequent trace check includes every selected audit/migration behavior file as well.

### Source operational checks

- Controlled suites excluding integration, focused loaders, matrix, and the inapplicable Linux suite: **139 discovered, 138 passed, 0 failed, 1 documented filesystem skip**. Audit.Common retains all four tests, including exactly one adverse-import "No audit files found" verbose message.
- Source matrix: **30 unique tuples discovered/passed**, L1–L5 crossed with ARM/AMR/RAM/RMA/MAR/MRA. Every tuple discovers 136 inner cases: 135 pass, zero fail, one documented case-sensitive-filesystem skip. Aggregate: **4,080 discovered, 4,050 passed, zero failed, 30 permitted skips**. Worker and driver accounting remain 136; the fixed public metadata snapshot is unchanged.
- Migration live SQL: **7 discovered/passed, 0 failed/skipped**, including real history, ordered execution, force/preview, SQL failure, history-write failure, and idempotent retry. Generated fast1_migration_test_* databases, including the case-sensitive fixture, were torn down by the suite.
- Archiving live SQL: **29 discovered/passed, 0 failed/skipped**. Existing cases exercise working sets, committed-copy/delete recovery, constraint restoration, cleanup, and configuration/primary-key requirements. Generated fast1_archiving_test_* config/source/destination databases were torn down by the suite.
- Audit live SQL: configured pester-srv share was initially unavailable. The user changed the fixture to \\lolo7050\audit\void; the first run observed 576 expected versus 606 imported records. SQL reported no active audit target, so the discrepancy was not established to be a changing file. On the user's requested recheck, **4 discovered/passed, 0 failed/skipped** against the current fixture. The generated fast1_audit_test_* database was torn down. No workflow, SQL, or audit assertion was changed to obtain this pass; preserve the user's fixture-path edit.

### Analyzer and remaining acceptance

Invoke-ScriptAnalyzer ran with initialized types, default rules (no repository settings), and Error/Warning severity. Final analysis of all 13 modified/new PowerShell files had **zero findings**, including the final expanded bootstrap trace. Seven affected success/instrumentation cases were rerun after that trace change: all seven passed (the other 40 focused cases were unchanged). No rules or package filters were changed. Existing multiline/tab formatting and public/SQL/workflow bodies are preserved.

Analyzed files beneath Fast1data.SqlServer/: Fast1data.SqlServer.psm1; private/shared/{Load.ps1,GenericSqlQuery.ps1}; private/archiving/{Load.ps1,ArchivingModel.psm1,Compare-Column.ps1,Invoke-ArchivingProcess.ps1}; private/migration/Set-Executed.ps1; tests/{ModuleLoaders.Tests.ps1,Audit.Integration.Windows.Tests.ps1}; tests/fixtures/{Invoke-ModuleLoaderScenario.ps1,SharedHelpers.Classes.ps1,SharedHelpers.Scenarios.ps1}.

Body comparisons against HEAD confirm that GenericSqlQuery, Set-Executed, Compare-Column, and Invoke-ArchivingProcess differ only before their behavior documentation/body, and ArchivingModel is identical from its first local function through all classes/exports. Public functions, manifest, type-only modules, SQL/schema, dependency build, packaging script, and fixed public-contract snapshot have no changes. git diff --check passes. The original cleanup inclusion edits are retained through shared Load rather than duplicate entry-point lists.

The first real out/publish.ps1 invocation staged the files and passed analyzer, then failed because sandbox restrictions denied Pester registry setup. The unrestricted rerun **passed with exit code 0**, without changing package code or suppressing checks: **281 discovered, 255 passed, zero failed, 26 expected skips**. Of the skips, 25 are inapplicable Linux audit cases (21 controlled, four integration) and one is the documented case-sensitive-filesystem case. The full package analyzer passed with its existing configuration/filter unchanged. The locally staged module is version 0.0.4; no gallery publication occurred.

All 23 private files, manifest/root, and changed test/fixture files (29 compared files) match source hashes; both new loaders, all fixtures, and all three runtime DLLs are staged. The package matrix discovered/passed **30 unique tuples**, each with 136 inner cases: **4,080 total, 4,050 passed, zero failed, 30 permitted filesystem skips**. Every normalized tuple result exactly matches source. Fixed public metadata and normalized operation/logging expectations pass in both distributions. Across source and package, all **60 tuples / 8,160 inner cases** are accounted for; 8,100 passed and 60 documented filesystem cases skipped.

### Independent staged-distribution checks (T029)

All commands in this section start fresh pwsh -NoLogo -NoProfile processes and select only out/Fast1data.SqlServer test/module/worker paths. The package matrix uses the publisher's 30 independently spawned workers, each with its own process and selected-package provenance checks; its complete results are recorded with the package gate below.

| Independent check | Discovered | Passed | Failed | Skipped |
|---|---:|---:|---:|---:|
| Focused loaders | 47 | 47 | 0 | 0 |
| Applicable controlled suites | 139 | 138 | 0 | 1 |
| Migration live SQL | 7 | 7 | 0 | 0 |
| Audit live SQL | 4 | 4 | 0 | 0 |
| Archiving live SQL | 29 | 29 | 0 | 0 |

The one skip is the same documented filesystem case as source. The independent loader run produced all 44 expected complete worker records (the other three cases are AST/structure checks); its uninstrumented cold direct import resolved both root and bundled SqlClient beneath C:/Dev/Fast1data.SqlServer/out/Fast1data.SqlServer. Model/type modules and helper functions satisfy selected-distribution checks; manifest imports, model-first imports, compatible reuse, fault isolation, and all feature bootstrap traces pass. Normalized names/results for all 139 controlled cases are identical between source and package. Each live suite selected fresh generated disposable databases and completed its teardown.

Windows source and package acceptance is complete. Other hosts are unavailable: WSL is not installed, and no Linux/macOS execution host is configured. Their runtime files existing on Windows is not host acceptance. SC-004 remains unverified across the full supported host set, and T030 remains unchecked. T001–T029 and T031–T033 are complete: **32 of 33 tasks**. No required implementation work remains on the available host; the outstanding gate is execution on Linux/macOS.

### Host coverage and hooks

| Host | Source/package execution | Status |
|---|---|---|
| Windows x64 / PowerShell Core 7.6.9 | Cold imports, loader faults, ownership/types, controlled suites, matrix, live SQL, analyzer, local package gate | PASS |
| Linux x64 | No execution host; WSL is not installed | Unverified; T030 remains open |
| macOS x64 | No execution host configured | Unverified; T030 remains open |

All three runtime asset directories are present in source and stage. Audit discovery retains its Windows/Linux restriction. No .specify/extensions.yml exists, so no before/after implementation hooks are registered.
