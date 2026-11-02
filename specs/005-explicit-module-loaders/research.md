# Research: Explicit Module Loaders

Research date: 2026-11-01. Baseline: current `dev` working tree and [spec.md](spec.md), with [feature 004](../004-isolate-shared-helpers/spec.md) as the compatibility contract. Research inspected current files rather than relying on earlier plans. No production files were changed by this planning workflow.

## 1. Complete dependency inventory

**Decision**: Keep one authoritative shared behavior list with five files/eight functions. Retain checksum and relative-path helpers because they already belong to `private/shared`; both consumers receive the complete retained set. Bootstrap helpers and type declarations remain separate.

Paths below are relative to `Fast1data.SqlServer/private/`. The table accounts for all 21 existing private files; the two planned loader scripts are additional.

| Owner | Files | Defined functions/types |
|---|---|---|
| Assembly bootstrap | `shared/Get-RuntimeIdentifier.ps1`, `shared/Import-SqlClientLib.ps1` | `Get-RuntimeIdentifier`, `Import-SqlClientLib` |
| Shared behavior | `shared/GenericSqlCleanup.ps1` | `Close-GenericSqlResource`, `Add-GenericSqlCleanupFailure`, `Get-GenericSqlCleanupFailure` |
| Shared behavior | `shared/GenericSqlQuery.ps1` | `Get-GenericSqlCommand`, `Invoke-GenericSqlQuery` |
| Shared behavior | `shared/Write-LogMessage.ps1` | `Write-LogMessage` |
| Shared behavior | `shared/Get-FileChecksum.ps1` | `Get-FileChecksum` |
| Shared behavior | `shared/Get-RelativePath.ps1` | `Get-RelativePath` |
| Shared type declaration | `shared/GenericSqlParam.psm1` | `GenericSqlParam` |
| Root audit | `audit/Get-ImportState.ps1`, `audit/Get-SqlAuditFile.ps1`, `audit/Get-SqlAuditFileEntry.ps1`, `audit/Import-SqlAuditFile.ps1` | Same-name functions |
| Root migration | `migration/Get-Executed.ps1`, `migration/Set-Executed.ps1`, `migration/Resolve-MigrationPhase.ps1`, `migration/Invoke-Migration.ps1` | Same-name functions |
| Root adapter | `archiving/Invoke-ArchivingProcess.ps1` | `Invoke-ArchivingProcess` |
| Model helper files | `archiving/Get-DelayIntervalInSecond.ps1`, `archiving/Compare-Column.ps1` | Same-name functions |
| Model metadata | `archiving/Metadata.psm1` | `TableColumn`, `IndexColumn`, `Index` |
| Model entry point | `archiving/ArchivingModel.psm1` | `TableGroup`, `ProcessState`, `Table`; seven functions below |

Model-local functions: `Get-ArchivingConnection`, `Get-ArchivingCommand`, `Get-ArchivingTable`, `Get-ArchivingBulkCopy`, `Get-ArchivingServerIdentity`, `ConvertTo-ArchivingIdentifier`, `Invoke-ArchivingConstraintAction`.

**Rationale**: Explicit ownership accounts for every dependency without moving behavior. Comparison/delay functions stop being accidentally loaded into root by recursion.

**Alternatives considered**: Duplicate shared lists (fails FR-001); move checksum/path helpers into migration (unnecessary scope change); introduce a shared service/module (fails the required independent consumer scopes); retain discovery/exclusions (fails FR-003).

## 2. Type availability and assembly ordering

**Decision**: Root declares `using module ./private/shared/GenericSqlParam.psm1` before runtime statements. This class-only file uses built-in types and initializes no feature behavior. Retain model declarations for GenericSqlParam, Metadata, and its namespace. Add declaration-only `private/archiving/Load.ps1` with `using module ./ArchivingModel.psm1` and explanatory comments. Root dot-sources it after SqlClient bootstrap and before separately loading the adapter.

Remove these ordinary-function dependencies:

| File | Directive removed | Owning loader supplies dependency |
|---|---|---|
| `shared/GenericSqlQuery.ps1` | Parameter-class declaration | Root/model declarations |
| `migration/Set-Executed.ps1` | Parameter declaration and query dot-source | Root declaration and shared loader |
| `archiving/Compare-Column.ps1` | Metadata declaration | Model declaration |
| `archiving/Invoke-ArchivingProcess.ps1` | Model declaration | Root's staged archiving declaration script |

**Rationale**: PowerShell processes using declarations before ordinary runtime statements; Import-Module alone does not import classes into the consumer's type context. Model class declarations require SqlClient types before compilation. An eager root model declaration can therefore precede assembly initialization. A separately parsed declaration script stages this correctly while preserving the adapter's `[TableGroup]::new(...)`. Relative declaration paths resolve from their declaring script. See Microsoft's [about_Using](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_using?view=powershell-7.6).

Dot-sourcing runs in the current scope, letting shared functions belong independently to root/model. See [about_Scripts](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts?view=powershell-7.6). Class definitions remain tied to their defining module; changed-class hot reload remains outside scope. See [about_Classes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-7.6).

**Experimental evidence**: A research agent ran fresh PowerShell 7.6.9 probes including a disposable copy of real private/public files and manifest with the proposed loaders/removals. Observed: three public commands, zero model exports, distinct root/model logger owners, GenericSqlParam construction in both scopes, unchanged adapter construction of TableGroup reaching the model-local substituted connection seam, preserved controlled primary error, and successful metadata-typed Compare-Column calls. Propagation from a dot-sourced declaration script into subsequently dot-sourced behavior was established experimentally rather than assumed from documentation.

The installed SqlServer module supplied SqlClient in the real-code probe. This establishes type/scope feasibility, not bundled-assembly loading, package completeness, or negative behavior. Those require independent cold checks.

**Alternatives considered**: Eager root model declaration (unsafe ordering); runtime Import-Module alone (insufficient class visibility); constructor handles/factories (unnecessary behavior-interface change); dynamic scripts/global accelerators (unnecessary state/complexity); third behavior module (violates required scopes).

## 3. Runtime stages and failure handling

**Decision**: Root runs bootstrap helper definitions and Import-SqlClientLib first; then shared Load, explicit audit/migration lists, staged archiving declarations and adapter, and existing public loading/exports. Model's declarations precede shared Load and explicit delay/comparison loads. Model retains its existing functions/classes and empty function/alias exports.

Use literal dot-sources or ordered literal path arrays at the designated loaders. Shared Load selects cleanup, query, logger, checksum, and relative-path files in that order. It discovers no files, executes no feature operations, caches nothing, and creates no new scope. Bootstrap stays outside its behavior list.

**Rationale**: Existing assembly initialization is process-idempotent and gives runtime/path context for missing assets. Preserve this. Required script/assembly errors must terminate initialization with safe dependency context. Loader-level error handling may temporarily use a consumer-scoped ErrorActionPreference, restored in finally; do not change caller preferences or swallow original details. Declaration failures already identify missing module paths; preserve their parser/import context.

Model-first paths retain explicit assembly bootstrap before model import/parsing. Model runtime cannot bootstrap types needed for its own compilation. Manifest-required SqlServer loading occurs before root runtime and may satisfy SqlClient already; first-stage ordering concerns root runtime code.

**Alternatives considered**: Continue after dot-source errors (fails FR-007); bootstrap only inside model runtime (too late); add a general dependency framework (unnecessary for this inventory).

## 4. Verification and packaging

**Decision**: Reuse regression suites and the 30-tuple per-distribution matrix, update ownership expectations, and add focused ModuleLoaders.Tests.ps1 coverage. Use clean subprocesses/disposable distribution copies for cold imports, sentinels, and required-dependency failures.

**Rationale and findings**:

- SharedHelpers.Scenarios currently expects comparison/delay in both modules and checksum/path only in root. Update to the intended owners while preserving module/session-state identity checks.
- Invoke-SharedHelperScenario preloads SqlClient for every L1–L5 case. Add a root import without external bootstrap. For negative assembly checks, use the root psm1 in a fresh process where necessary to avoid manifest-required SqlServer incidentally supplying the assembly.
- Both worker and outer matrix hardcode 136 inner cases. Keep both synchronized if their contained cases change. New focused cases outside the matrix need not change its total.
- Retain the seven-type fixture, both Execute overloads, single-use guard, real loggers, six operation orders, caller preferences, and unchanged audit regression.
- out/publish.ps1 copies private files/fixtures, validates assets/manifest, analyzes scripts, and runs all tests including live integration. It stages locally without gallery publication. A staged directory after failure is not a validated package.
- build/build.ps1 rebuilds dependencies for all three x64 runtime identifiers. No asset/dependency changes are planned. Packaging changes only if validation exposes a missing path.
- No repository analyzer settings were found. Packaging has an existing SqlClient TypeNotFound filter; do not extend this bypass. Analyze changed scripts with types initialized and report remaining findings.

**Alternatives considered**: Static checks alone (miss class/runtime errors); existing matrix alone (masks bootstrap); package validation in source session (masks files/class identity); unrelated fixture/schema redesign (outside scope).

## 5. Planning evidence and remaining checks

The root agent ran Audit.Common.Tests.ps1 in a fresh Windows/PowerShell 7.6.9/Pester 6.2.0 process: **4 passed, 0 failed, 0 skipped**. Local tools include SqlServer 22.4.5.1 and PSScriptAnalyzer 1.25.0. This current baseline supersedes the older feature 004 planning failure.

Full matrix, release packaging, live SQL, Linux, and macOS acceptance were not run for this feature during planning. Planning outputs are Markdown only; no new script analyzer run is required. Technical unknowns are resolved by repository evidence and isolated probes; implementation execution obligations remain in [quickstart.md](quickstart.md).

