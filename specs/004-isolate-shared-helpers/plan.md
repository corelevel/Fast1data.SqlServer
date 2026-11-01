# Implementation Plan: Predictable Internal Imports and Isolated Shared Helpers

**Branch**: `dev` | **Feature identifier**: `004-isolate-shared-helpers` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: `specs/004-isolate-shared-helpers/spec.md`

The setup script reports `004-isolate-shared-helpers` as `BRANCH` from the feature directory. The actual Git branch is `dev`; this workflow does not create or switch branches.

## Summary

Keep shared helpers local to their intended module session states. Explicitly suppress function and alias exports from `ArchivingModel.psm1`, preserving its local SQL, cleanup, comparison, delay, and logging dependencies and existing `using module` class imports. Retain the root module's local helpers and its three public commands.

Export isolation fixes the audit helper collision but is insufficient for archiving verbosity. Forward the effective invocation `$VerbosePreference` through the existing internal adapter into an additive `TableGroup.Execute([System.Management.Automation.ActionPreference]$VerbosePreference)` overload. The overload delegates to the existing parameterless execution method; its method-local preference reaches nested model methods and private loggers. Keep `Execute()` and existing constructors available. Do not assign preferences to shared module or global scope.

Validate helper ownership separately from public exports, and exercise real logging and class execution in fresh processes across imports, all six public-operation orders, and both source and staged package distributions. Preserve SQL and cleanup semantics, including the generic non-query helper's deliberate absence of output.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core; PowerShell classes and script modules. Existing dependency build targets .NET 10.

**Primary Dependencies**: Existing SqlServer module, Microsoft.Data.SqlClient 7.1.1, System.Security.Cryptography.Pkcs 10.0.14. Pester 6+ for the existing packaging path and PSScriptAnalyzer. No dependency changes.

**Storage**: Existing SQL Server audit offsets, migration history, archiving configuration, working tables, and process state. No schema, configuration, or persisted-data changes.

**Testing**: Pester controlled fixtures, child-process import/operation matrix, literal `using module` class probes, existing SQL Server integration suites, and PSScriptAnalyzer on every modified PowerShell file. Preserve the existing audit regression and exact message count.

**Target Platform**: x64 Windows, Linux, and macOS module/runtime support. Audit discovery retains its Windows/Linux restriction; macOS checks cover supported import, classes, shared helpers, migration/archiving, and existing unsupported-discovery behavior.

**Project Type**: PowerShell SQL Server automation module with three public commands.

**Performance Goals**: Preserve batching and query counts; add no database round trips, per-record module imports, or buffering. The preference bridge adds one call per archiving invocation. No new throughput SLA.

**Constraints**: Stable public signatures, class availability, logging streams/format, primary errors, cleanup order, constraints, checksums, checkpoints, retry behavior, and runtime assets. Multiline control-flow blocks with tabs per `AGENTS.md`. No secrets in artifacts or logs.

**Scale/Scope**: Two production files expected to change: `private/archiving/ArchivingModel.psm1` and `private/archiving/Invoke-ArchivingProcess.ps1`. Tests and validation documentation expand. Root loader, logger, SQL bodies, manifest, and packaging script change only if acceptance evidence demonstrates a necessary defect in this boundary design.

## Constitution Check

The pre-research gate passed on scope and compatibility commitments. The post-design gate passes with the obligations below. These are design assessments, not claims that implementation or release checks have passed.

| Gate | Pre-research assessment | Post-design evidence and required validation |
|---|---|---|
| I. Data integrity and resumability | Preserve existing progress and recovery | No SQL/state transitions change. Reuse audit offset, archiving interruption/checkpoint/retry, and migration history-failure fixtures in both distributions. SQL integration verifies durable effects and constraint recovery. |
| II. Deterministic migrations | No phase/order/checksum/preview changes | Retain migration validation, script-order, SHA-256, force/ignore, `-WhatIf`, and stop-on-error cases; exercise migration after other operations. |
| III. Explicit database operations | Preserve bounded parameterized operations and primary errors | Inventory SQL/cleanup consumers; verify scalar and no-output non-query contracts, disposal and error identity. Live checks require selected disposable databases and documented permissions. |
| IV. Portable PowerShell contracts | Preserve commands, types, runtime, and assets | Empty model function exports preserve class definitions. Verify literal `using module`, unchanged parameter metadata, three public exports, declared assets, and supported host paths. |
| V. Verification and visibility | Require regression and packaging evidence | Retain audit assertion; add real archiving logger checks, owner assertions, both distributions, and preference matrix. Record missing SQL/host checks as unverified. |
| Development workflow and analysis | Focused implementation; no exception | Analyze every changed PowerShell file using repository settings if present. Resolve new warnings/errors and report existing findings; add no bypass suppressions. |

No unjustified constitution violation or unresolved design clarification remains. Unavailable SQL/host execution is a later validation obligation; material unverified data-integrity risks block release.

## Project Structure

### Documentation (this feature)

```text
specs/004-isolate-shared-helpers/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── shared-helper-boundaries.md
└── checklists/requirements.md
```

`tasks.md` is a subsequent `$speckit-tasks` output and is not generated by this command.

### Source Code (repository root)

```text
Fast1data.SqlServer/
├── Fast1data.SqlServer.psd1
├── Fast1data.SqlServer.psm1
├── public/Invoke-Fast1{Audit,Archiving,Migration}.ps1
├── private/
│   ├── shared/
│   ├── audit/
│   ├── migration/
│   └── archiving/
│       ├── ArchivingModel.psm1
│       ├── Invoke-ArchivingProcess.ps1
│       └── Metadata.psm1
├── tests/
│   ├── Audit.Common.Tests.ps1
│   ├── Archiving.Execution.Tests.ps1
│   ├── SqlCleanup.Tests.ps1
│   ├── Migration*.Tests.ps1
│   ├── *Integration*.Tests.ps1
│   ├── SharedHelpers.Import.Tests.ps1       # Planned matrix driver
│   └── fixtures/                           # Planned child-process fixtures
│       ├── Invoke-SharedHelperScenario.ps1
│       └── SharedHelpers.Classes.ps1
├── schema/
└── lib/{win-x64,linux-x64,osx-x64}/
build/{build.ps1,SqlClientLoader.csproj}
out/publish.ps1
```

**Structure Decision**: Extend existing module/test boundaries. Workers sit beneath `tests/fixtures`, without `.Tests.ps1` names, so ordinary Pester discovery cannot recursively launch the matrix. They explicitly run their controlled assertions/Pester containers. Resolve paths from the selected distribution and assert that loaded internal modules belong to it.

## Phase 0: Research Outcome

[research.md](research.md) records inventory, ownership decisions, class/verbosity experiments, SQL/cleanup compatibility, and packaging constraints. Research confirmed two distinct needs: prevent model exports replacing root functions, and carry the invocation's verbose preference across the class-module boundary.

Planning baseline: `Audit.Common.Tests.ps1` produced 3 passes and 1 failure: the retained regression expected one message and received none. Isolated scoped-overload experiments passed all six ambient/explicit verbosity combinations, retained class construction, and exported zero model functions. This is feasibility evidence, not implementation acceptance.

## Phase 1: Design and Verification Approach

1. Restrict model function/alias exports explicitly, retaining local dot-sourced dependencies. Keep class-only metadata and SQL-parameter modules as type dependencies; assert no command exports from them.
2. Forward effective `$VerbosePreference` from the adapter into the additive execution overload. Use the bound preference, not merely the presence of `Verbose` in `$PSBoundParameters`, so explicit false and inherited settings work. Preserve the parameterless path and single-use execution guard.
3. Add real-logger archiving scenarios. Existing lifecycle tests that mock logging remain useful but do not count as stream coverage. Replace the adapter test's literal `.Execute()` source assertion with behavior verifying one execution, since the compatible overload changes the call expression.
4. Run fresh workers for five loading scenarios × six operation orders per distribution. Within each worker exercise all preference combinations, sequential on/off checks, owner/export assertions, class availability, and representative SQL/cleanup cases. Include class-only modules from the inventory; do not require changed-class hot reload.
5. Reuse success, failure, cleanup, interruption, and retry suites against both roots. Complete SQL-specific checks on a selected disposable SQL Server environment after adverse imports. Preserve primary error identity and migration termination.
6. Validate the real packaging path and runtime assets, then run package acceptance in clean processes. Packaging runs live SQL suites; a partially staged directory after failure is not a passing release package.

See [data-model.md](data-model.md), [contracts/shared-helper-boundaries.md](contracts/shared-helper-boundaries.md), and [quickstart.md](quickstart.md).

## Complexity Tracking

No constitution exceptions. The only production interface addition is an overload on an existing internal execution class, justified by demonstrated cross-module preference behavior. No new logging framework, dependency container, shared runtime service, or database abstraction.
