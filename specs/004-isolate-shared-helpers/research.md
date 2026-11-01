# Research: Shared Helper Isolation

**Feature**: `004-isolate-shared-helpers` | **Date**: 2026-11-01

## 1. Helper ownership and import boundary

**Decision**: Keep source sharing through dot-sourcing, with separate root and archiving-model function instances. Add explicit empty function/alias exports to `ArchivingModel.psm1`. Keep the manifest's three-command allowlist.

**Rationale**: The root loads shared functions locally and archiving scripts using the model. The model also dot-sources shared functions but has no export restriction. Its imported functions can replace root functions even when their source text is identical, because their session-state ownership differs. A manifest allowlist does not protect internal lookup. Microsoft documents default function/alias exports and explicit suppression. [Export-ModuleMember](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/export-modulemember?view=powershell-7.6)

**Alternatives considered**: Reordering enumeration fails after later imports. Renaming every helper creates unnecessary churn. Exporting generic helpers retains cross-module coupling. A shared runtime module introduces more preference boundaries. Replacing `using module` risks class compatibility.

### Dependency inventory

Paths are relative to `Fast1data.SqlServer/private/`. “Root” means the `Fast1data.SqlServer.psm1` session state; “Model” means `archiving/ArchivingModel.psm1`. Multiple local copies are intentional.

| Definition | Intended owner(s) | Consumers and loading path |
|---|---|---|
| `shared/Write-LogMessage.ps1`: `Write-LogMessage` | Root and Model | Root audit/migration and comparison callers; model `TableGroup`, `Table`, and comparison paths. Both owners dot-source it. |
| `shared/GenericSqlQuery.ps1`: `Get-GenericSqlCommand`, `Invoke-GenericSqlQuery` | Root and Model | Root migration history writes; model server-identity, constraints, process-state and table operations. Query helpers resolve their owner's factories and cleanup functions. |
| `shared/GenericSqlCleanup.ps1`: `Close-GenericSqlResource`, `Add-GenericSqlCleanupFailure`, `Get-GenericSqlCleanupFailure` | Root and Model | Root audit/migration resources; model execution, resources, constraints and nested SQL failures. Loaded through each owner's query source. Root excludes separate duplicate loading. |
| `shared/GenericSqlParam.psm1`: `GenericSqlParam` | Class module | `using module` from query source, migration `Set-Executed`, and model. No function exports needed. |
| `archiving/Metadata.psm1`: metadata types | Class module | `using module` from model and `Compare-Column`. Retain type names/fields; no command exports. |
| `archiving/Compare-Column.ps1`: `Compare-Column` | Root and Model under existing loader | Model table preparation and comparison callers. Logger resolves in the same owner. |
| `archiving/Get-DelayIntervalInSecond.ps1`: `Get-DelayIntervalInSecond` | Root and Model under existing loader | Model source-table initialization. No export or consolidation needed. |
| Model factories/actions: `Get-ArchivingConnection`, `Get-ArchivingCommand`, `Get-ArchivingTable`, `Get-ArchivingBulkCopy`, `Get-ArchivingServerIdentity`, `ConvertTo-ArchivingIdentifier`, `Invoke-ArchivingConstraintAction` | Model only | Archiving classes/model helpers. Tests can mock inside model scope; production consumers need no exported functions. |
| `shared/Get-RuntimeIdentifier.ps1`, `shared/Import-SqlClientLib.ps1` | Root; explicit bootstrap for isolated class fixtures | Root loads bundled assemblies before private scripts. Model-first fixtures bootstrap assemblies without importing root first. |
| `shared/Get-FileChecksum.ps1`, `shared/Get-RelativePath.ps1` | Root only | Migration phase resolution/script matching; ownership must survive imports. |
| `archiving/Invoke-ArchivingProcess.ps1`: `Invoke-ArchivingProcess` | Root only | Public archiving command; imports model types, constructs `TableGroup`, calls execution entry point. |

Component-specific audit/migration functions remain root-local. No other production `.psm1` modules were identified beyond root, model, metadata, and SQL-parameter modules.

## 2. Class availability and invocation preferences

**Decision**: Preserve `using module`, constructors, and parameterless `TableGroup.Execute()`. Add an overload accepting a method-local `[System.Management.Automation.ActionPreference]$VerbosePreference`, delegating to `Execute()`. The root-local adapter passes the effective invocation preference.

**Rationale**: Empty function exports preserve class construction via `using module`. Class imports and command exports are separate mechanisms; use fresh processes after class-definition changes. [PowerShell classes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-7.6)

An isolated two-module experiment found that export restriction alone still lost explicit verbosity across a class-module boundary. A second experiment used a public advanced function, internal adapter, overload, parameterless method, second class method, comparison function, and private advanced logger. Passing the effective preference produced:

| Ambient | Invocation override | Verbose records |
|---|---|---:|
| SilentlyContinue | true | 1 |
| SilentlyContinue | false | 0 |
| SilentlyContinue | absent | 0 |
| Continue | true | 1 |
| Continue | false | 0 |
| Continue | absent | 1 |

Ambient preferences remained unchanged; class construction worked and the model exported zero functions. This establishes feasibility through nested calls. Implementation must repeat the assertions with real archiving operations and the existing logger. Parameterless class callers retain their applicable ambient behavior. The bridge changes no warning-stream routing or suppression policy.

**Alternatives considered**: Checking only presence of `Verbose` misses false/inheritance. Unconditional verbose writes break suppression. Shared module/global preference writes couple requests and failure paths. Logger callbacks or stored logging state on every table are unnecessary for the demonstrated scoped solution.

## 3. SQL and cleanup contracts

**Decision**: Leave SQL and cleanup implementations unchanged; test behavior in both local owners and through model class execution.

**Rationale**: The reported defect proves logging failure, not SQL corruption. `Invoke-GenericSqlQuery` sets text/type, validates `GenericSqlParam`, forwards size/precision/scale, maps null to `DBNull`, returns scalar values, and deliberately suppresses non-query results. Cleanup disposes owned commands while retaining borrowed connections. Audit result columns and model row counters keep their separate contracts.

Cleanup attempts all resources in order, preserves a primary error, or throws the first disposal failure after all attempts. Context uses `Fast1Sql.CleanupFailures` / `Fast1Archiving.CleanupFailures`. Model execution enriches context and restores constraints under existing rules. `SqlCleanup.Tests.ps1` and `Archiving.Execution.Tests.ps1` provide controlled seams; live suites are needed for durable effects and foreign-key state.

**Alternatives considered**: SQL rewrites or added affected-row output change unrelated contracts. Source comparison cannot establish ownership. Mocking the query helper in every model case does not prove its local dependencies remain functional.

## 4. Acceptance harness and distribution parity

**Decision**: Run five loading scenarios and six operation orders per distribution in fresh child processes. Exercise preferences and representative query/cleanup cases within workers; run source and package suites independently. Use real commands, class methods, and loggers with controlled discovery/SQL boundaries.

**Rationale**: Existing archiving lifecycle fixtures mock logging and cannot prove stream behavior. Public exports can remain correct despite helper replacement. Module/class caching can hide package fallback. Assert paths, owners, and outputs independently; normalize timestamps only for message comparisons.

**Alternatives considered**: Favorable import order, shared process across distributions, logger-mock counts, AST-only checks, or new concurrency requirements do not supply the requested evidence.

## 5. Build, platform, and validation prerequisites

**Decision**: Use existing dependency build and actual packaging path. Distinguish controlled acceptance from complete release validation.

**Rationale**: `build/build.ps1` builds all three runtime identifiers. `out/publish.ps1` copies implementation, tests, schema, and assets, validates the manifest, runs analyzer, and runs all tests including live integration. It stages locally and does not publish remotely. Its current SqlClient analyzer filter does not replace direct analysis of modified files and must not be extended to bypass findings.

Integration suites have editable local settings, not a supported environment-variable configuration interface. They create unique databases on a selected disposable SQL instance. Audit needs closed files, shared access, and Linux `smbclient` where applicable. Tool availability does not establish SQL/alternate-host availability.

**Alternatives considered**: Treating a copied folder as a successful package misses the build path. Running all tests as an offline command performs database setup. A new skip-validation release switch is outside scope.

## Recorded evidence and remaining execution obligations

- Planning baseline on PowerShell 7.6.6 / Pester 6.2.0: audit common suite has 3 passes and 1 failure; the retained regression receives zero instead of one verbose record.
- Scoped preference feasibility probe passed the six combinations above without preference mutation or function exports. This is not repository implementation acceptance.
- PSScriptAnalyzer 1.25.0 and SqlServer 22.4.5.1 were available during research; these are observed versions, not new minimums.
- No production files changed during planning. Live SQL, complete package execution, and alternate-platform acceptance remain to run during implementation.
- All design unknowns are resolved. SQL instance selection and host availability remain execution prerequisites.

## Implementation findings

The implementation changes only the model's explicit empty function/alias exports and an additive execution overload, plus the adapter's forwarding call/help. Real audit and nested archiving progress tests reproduced missing output before the repair and pass afterward. The root and model retain separate defining session states for the shared helper inventory.

Forced unchanged-model imports require precise test-seam targeting: the root's parsed classes retain the original nested model even when a refreshed model is registered. Pester's nested module name `Fast1data.SqlServer/ArchivingModel` targets that original owner. The completed L5 scenario forces model, Metadata and GenericSqlParam twice, exercises the retained class owner, and checks the refreshed model independently. No global mocking mode or class hot-reload mechanism is used.

Fixed public metadata also records command-level attributes (including SupportsShouldProcess) from the unchanged public sources at the baseline revision. Migration stream tests normalize timestamp/level prefixes while preserving exact semantic messages and stream types.

Live source validation passed 40 tests on the existing disposable SQL fixture, covering durable recovery, foreign-key restoration and Linux SMB audit progress. Final source/package matrix, packaging and platform status are recorded in [validation.md](validation.md); unavailable hosts remain explicit acceptance obligations.
