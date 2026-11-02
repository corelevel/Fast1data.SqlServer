# Implementation Plan: Explicit Module Loaders and One Shared Loading List

**Branch**: `dev` | **Feature identifier**: `005-explicit-module-loaders` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: `specs/005-explicit-module-loaders/spec.md`

Setup reports `005-explicit-module-loaders` as `BRANCH` from the feature-directory name. The actual Git branch remains `dev`; this workflow does not create or switch branches.

## Summary

Replace recursive private-script discovery with explicit dependency lists in the existing root and archiving model entry points. Introduce `private/shared/Load.ps1` as the only shared behavior list: five files defining eight functions, dot-sourced independently into each consuming module. Keep assembly bootstrap separate and first at runtime, and retain three public commands and two behavior module scopes.

Move type dependencies out of four ordinary function files. Root declares the assembly-independent `GenericSqlParam` dependency; model retains its parameter and metadata declarations. A declaration-only `private/archiving/Load.ps1`, dot-sourced by root after assembly bootstrap, imports model classes before root explicitly loads `Invoke-ArchivingProcess.ps1`. This supplies the language-required declaration boundary without introducing another module scope or changing class construction.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core and PowerShell classes; existing dependency build targets .NET 10.

**Primary Dependencies**: Existing SqlServer module, Microsoft.Data.SqlClient 7.1.1, System.Security.Cryptography.Pkcs 10.0.14; no new runtime dependencies. Local validation tools: Pester 6.2.0 and PSScriptAnalyzer 1.25.0.

**Storage**: Existing SQL Server audit offsets, migration history, archiving configuration, working sets, and checkpoints. No schema, storage, or configuration changes.

**Testing**: Existing Pester suites and fresh-process import/order matrix; focused loader structure, required-dependency failure, and cold import checks; separate source/package checks; relevant existing SQL Server integration coverage; analyzer on every modified PowerShell file.

**Target Platform**: x64 Windows, Linux, and macOS. Audit discovery retains its Windows/Linux restriction. Planning probes ran on Windows/PowerShell 7.6.9; other hosts remain implementation validation obligations.

**Project Type**: PowerShell module with audit, migration, and archiving commands.

**Performance Goals**: Bounded explicit loading without private-directory traversal. Two shared-loader executions are intentional. No new per-record work, SQL calls, or throughput target.

**Constraints**: Preserve ownership, classes, export/parameter metadata, logging preferences, SQL results, cleanup, order, progress, and retries. Use portable module-relative paths and tab-indented multiline PowerShell blocks per `AGENTS.md`. Preserve existing user source edits during planning.

**Scale/Scope**: Account for all 21 existing private files. Add two loader scripts; revise root/model entry points and remove dependency directives from four function files. Extend tests/fixtures and affected maintainer guidance. No SQL, manifest contract, runtime asset, or public-function changes are planned.

## Constitution Check

Pre-research assessment: PASS on bounded scope and compatibility commitments. Post-design assessment: PASS with the obligations below. These assessments do not claim future implementation checks have passed.

| Gate | Pre-research commitment | Post-design assessment and required evidence |
|---|---|---|
| I. Integrity and resumability | Preserve durable work and retries | No workflow/SQL/state bodies change. Retain interruption, ignored audit-record offsets, archive/purge order, working sets, and retry coverage. |
| II. Deterministic migrations | Preserve phases, ordering, checksums, history, and preview | Keep duplicate/path/force/ignore validation, SHA-256 checks, `-WhatIf`, termination, and history-failure fixtures. |
| III. Explicit database operations | Preserve bounded SQL, primary errors, and cleanup | Retain query parameter/result contracts, resource order and error attachment. Live SQL uses selected disposable databases and documented fixture permissions. No credentials in artifacts. |
| IV. Portable contracts | Preserve runtime, commands, classes, and assets | Exactly three root commands; no model helper exports. Test module-relative paths, literal class imports, distribution ownership, and all runtime directories. |
| V. Verification and visibility | Validate affected imports/builds and messages | Add cold imports, sentinel/dependency failures, and ownership checks; retain real loggers, metadata comparisons, source/package matrix, and relevant SQL suites. |
| Development workflow | Focused scope; analyze every changed script | Use repository analyzer settings if present; none were found during planning. Resolve new warnings/errors without bypasses; report existing findings and unavailable checks. |

No constitution exception or unresolved design clarification remains. Unrun host, packaging, and SQL checks remain unverified; unresolved material integrity risks block release.

## Project Structure

### Documentation (this feature)

```text
specs/005-explicit-module-loaders/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/loader-boundaries.md
└── checklists/requirements.md
```

`tasks.md` belongs to the subsequent `$speckit-tasks` workflow and is not generated here.

### Source Code (repository root)

```text
Fast1data.SqlServer/
├── Fast1data.SqlServer.{psd1,psm1}
├── public/Invoke-Fast1{Audit,Migration,Archiving}.ps1
├── private/
│   ├── shared/
│   │   ├── Load.ps1                       # New: authoritative shared list
│   │   ├── GenericSqlParam.psm1
│   │   └── *.ps1                         # Existing behavior/bootstrap
│   ├── audit/*.ps1
│   ├── migration/*.ps1
│   └── archiving/
│       ├── Load.ps1                       # New: declaration-only loader
│       ├── ArchivingModel.psm1
│       ├── Metadata.psm1
│       └── *.ps1
├── tests/
│   ├── ModuleLoaders.Tests.ps1             # Planned focused loader tests
│   ├── SharedHelpers.Import.Tests.ps1
│   ├── Audit.Common.Tests.ps1
│   ├── {SqlCleanup,Archiving.Execution,Migration,Migration.Phase}.Tests.ps1
│   ├── *Integration*.Tests.ps1
│   └── fixtures/
└── lib/{win-x64,linux-x64,osx-x64}/
build/{build.ps1,SqlClientLoader.csproj}
out/publish.ps1
```

**Structure Decision**: Keep existing module/test boundaries. The archiving loading script contains only the literal model type declaration and explanatory comments; it adds no function, class, export, or module scope. Explicit lists replace private discovery. Existing public discovery/export mechanics may remain. Packaging already copies the entire private tree; no packaging edit is expected.

## Phase 0: Research Outcome

[research.md](research.md) resolves ownership, bootstrap ordering, declaration staging, failure handling, and validation integration. Two research agents inspected the inventory and type-loading options. The fresh-process audit baseline passed all four existing tests on 2026-11-01. Disposable real-code type/scope probes establish feasibility; they do not constitute implemented loader acceptance.

## Phase 1: Design and Verification Approach

1. Introduce the five-file shared behavior list, dot-sourced from root/model without caching or child-scope invocation. Bootstrap helpers and class-only modules stay outside this list.
2. Replace root private discovery/exclusions with explicit audit and migration lists, staged archiving declarations, and the adapter. Bootstrap SqlClient before behavior loads. Model explicitly selects only its archiving-specific helpers.
3. Move dependency directives out of `GenericSqlQuery.ps1`, `Set-Executed.ps1`, `Compare-Column.ps1`, and `Invoke-ArchivingProcess.ps1`. Preserve behavior bodies and typed class construction.
4. Make required loading failures terminating with safe dependency/stage context. Preserve original errors and caller preferences, and prevent public operations from continuing after partial initialization.
5. Add focused full-inventory, no-hidden-loading, sentinel, cold assembly-first, two-owner, class, and repeated-import checks. Update ownership expectations for checksum/path and archiving-only comparison/delay helpers.
6. Retain five loading scenarios and six operation orders per distribution. Existing workers preload SqlClient, so supplement them with independent cold imports. Keep exact case accounting; update both worker/driver totals only if their contained cases change.
7. Run affected controlled suites, required SQL Server checks, analyzer, and the actual packaging path. Repeat package acceptance in independent processes with no source-path fallback. Record unavailable platforms/prerequisites.

See [data-model.md](data-model.md), [contracts/loader-boundaries.md](contracts/loader-boundaries.md), and [quickstart.md](quickstart.md).

## Complexity Tracking

No constitution violations. The extra declaration-only script addresses PowerShell parsing: eager root-level model declarations can precede assembly bootstrap. Staging preserves existing behavior without a new module, factory interface, global accelerator, or dynamic code evaluation.

