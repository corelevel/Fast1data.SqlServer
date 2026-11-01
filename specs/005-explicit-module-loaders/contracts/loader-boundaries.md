# Contract: Explicit Loader Boundaries

Scope: internal loading plus the existing externally visible PowerShell command/type contract. See [spec.md](../spec.md) and the [dependency inventory](../research.md). This is a design contract for implementation.

## Loading entry points

| Entry point | Required responsibility |
|---|---|
| Fast1data.SqlServer.psm1 | Declare GenericSqlParam; visibly bootstrap SqlClient first at runtime; dot-source shared Load; explicitly select audit/migration files, staged model declaration, and archiving adapter; assemble existing public functions |
| private/shared/Load.ps1 | Only authoritative shared behavior list; dot-source the five shared behavior files into the calling consumer scope |
| private/archiving/Load.ps1 | Declaration-only `using module ./ArchivingModel.psm1`, plus comments; dot-sourced after bootstrap to make model types available before adapter loading |
| private/archiving/ArchivingModel.psm1 | Retain parameter/metadata declarations; dot-source shared Load and explicit comparison/delay helpers; retain existing local functions/classes and zero helper exports |

Root explicitly selects Get-ImportState, Get-SqlAuditFile, Get-SqlAuditFileEntry, Import-SqlAuditFile, Get-Executed, Set-Executed, Resolve-MigrationPhase, Invoke-Migration, and Invoke-ArchivingProcess. No recursive private discovery or exclusion list remains. Existing public-file discovery may remain.

Bootstrap comprises Get-RuntimeIdentifier, Import-SqlClientLib, and its invocation. It stays visibly separate from shared behavior. Type-only declarations required by the language may precede runtime bootstrap without executing feature behavior.

## Scope and ownership invariants

1. Each consumer defines its own eight shared functions. Command Module/SessionState references match that consumer and selected distribution.
2. Comparison/delay and seven model-local functions belong only to model; audit/migration/adapter behavior is assembled only by root.
3. Loading model does not replace root logger/query/cleanup functions. Neither consumer uses an external session's helper as a substitute for its own definition.
4. Shared Load executes once per actual consumer initialization, independently in both scopes; no cache, call operator, child module, or function wrapper discards/localizes its definitions.
5. Ordinary function files contain no dependency loading directives. Remove using declarations and dependency dot-sources from GenericSqlQuery, Set-Executed, Compare-Column, and Invoke-ArchivingProcess. Designated bootstrap support is distinguished from ordinary behavior.
6. An unlisted private file, including one nested beneath an existing private directory, executes no code during import.

## Public and type compatibility

Root exposes exactly Invoke-Fast1Audit, Invoke-Fast1Migration, and Invoke-Fast1Archiving. Preserve all parameter metadata and common-parameter behavior using the existing public-contract fixture. Export no private helpers, aliases, variables, or cmdlets. Model exports zero helper commands.

Preserve literal class imports, constructors, properties, TableGroup.Execute() and its preference overload, single-use behavior, GenericSqlParam checks, and metadata-typed comparisons. Root-first and explicitly bootstrapped model-first paths work in clean sessions. Existing supported repeated/forced internal imports remain covered; changed-class hot reload is not added.

Runtime/platform/dependency contracts and all win-x64/linux-x64/osx-x64 assets remain unchanged. No configuration or SQL upgrade is required.

## Errors and preferences

Missing selected scripts/type modules or failed assembly initialization terminate affected loading. Errors identify the dependency/stage and retain useful original details without secrets. Do not continue to usable public operations after partial initialization. Preserve existing process-idempotent assembly reuse.

If error preferences are temporarily strengthened within a consumer loader, restore them in finally, including failure paths. Preserve caller verbose, warning, and error preferences. Existing SQL failures, primary error identity, attached cleanup failures, resource disposal, query parameter/scalar/non-query contracts, checkpoints, migration ordering/preview, and retry behavior remain unchanged.

## Required acceptance evidence

| Requirement | Evidence |
|---|---|
| FR-001–002 | One shared production list, both entry-point references, per-consumer function ownership, two independent shared-loader executions |
| FR-003–004 | Complete inventory, explicit component selections, no recursive private discovery, inactive unlisted sentinel, correct exclusive ownership |
| FR-005–006 | No ordinary-file loading directives; type construction/typed calls; assembly-first runtime trace in a cold direct-root import |
| FR-007 | Missing shared script/loader/type module and missing/corrupt assembly fail in fresh disposable-copy processes; no operations proceed |
| FR-008 | Three exports, fixed public metadata, literal class fixture, repeated imports, 30 loading/order tuples per distribution |
| FR-009 | Existing real logger/preference, SQL, cleanup, workflow, durable-progress and retry regressions; required live SQL checks |
| SC-001–004 | Full inventory and list review, all expected cases discovered, no unexpected skips, normalized source/package parity |

The existing matrix prebootstraps SqlClient and does not prove cold initialization. Add separate cold root import coverage. A missing bundled assembly should fail only when no already initialized compatible assembly satisfies the existing bootstrap contract; ensure fault-injection workers do not accidentally preload it through SqlServer.

Tests may use controlled doubles for workflow seams, with real class dispatch/loggers where relevant. SQL Server-specific behavior retains live integration requirements. Source and package acceptance start in independent processes and assert selected-root file/module/assembly provenance. Record unavailable hosts/SQL/package checks as unverified.

