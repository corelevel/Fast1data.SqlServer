# Contract: Shared Helpers, Public Commands, and Class Consumers

## Public command compatibility

The root manifest continues exporting exactly these functions, with existing attributes, defaults, aliases, validation, and common parameters:

| Command | Existing declared parameters |
|---|---|
| `Invoke-Fast1Audit` | Mandatory string `ConnStr`, mandatory string `Folder`, optional `PSCredential Credential` |
| `Invoke-Fast1Archiving` | Mandatory string `ConnStr`, mandatory string `GroupName` |
| `Invoke-Fast1Migration` | Mandatory string `ConnStr`, mandatory validated string `BasePath`, mandatory string `Phase`, optional string arrays `IgnoreScripts`, `ForceScripts`; existing `SupportsShouldProcess` |

No new public function, alias, variable, or cmdlet exports. No configuration, schema, runtime, dependency, or data migration. Compare full command parameter metadata with the baseline rather than only names.

## Internal import and type boundary

- Root owns its locally loaded helpers. Model imports must not replace them, regardless of identical source text.
- `ArchivingModel.psm1` exports no functions or aliases. It retains its local query, cleanup, logger, comparison, delay, and factory/action dependencies.
- `Metadata.psm1` and `GenericSqlParam.psm1` continue providing their classes through existing `using module` paths and expose no helper commands.
- Existing `TableGroup`, `Table`, `ProcessState`, `GenericSqlParam`, `TableColumn`, `IndexColumn`, and `Index` construction/loading paths remain compatible. Direct class use needs the existing SQL-client assembly prerequisite.
- Existing `TableGroup.Execute()` remains available. The additive overload accepting an `ActionPreference` delegates once to it and changes only the invocation-local verbose scope. Existing execution, errors, cleanup, and single-use enforcement remain owned by the parameterless method.
- Unchanged-module repeated/forced import paths must work. This feature does not promise hot replacement of already parsed, changed class definitions.

Tests inspect function defining module/session state, resolved module path, and effective behavior. Text equality and root exported-command enumeration alone are insufficient.

## Operational logging

The shared logger retains `Message`, `Level` (`Verbose` default or `Warning`), and format `[yyyy-MM-dd HH:mm:ss.fff] [Level] Message`. Verbose records use stream 4; warnings use stream 3. Neither stream becomes success output unless the caller explicitly redirects it.

| Ambient verbosity | Explicit `Verbose` | Expected progress |
|---|---|---|
| Off | absent | None |
| On | absent | Existing messages once each |
| Off or on | true | Existing messages once each |
| Off or on | false | None |

Run all six combinations, followed by verbose→quiet and quiet→verbose sequences, and verify caller preferences unchanged on success and failure. Test an applicable function-local ambient caller as well as session ambient settings. Warning-producing paths with verbose off and warnings enabled must still emit warning records; retain existing warning/error semantics.

For empty audit discovery, preserve the existing regression's total collection count of exactly one and its `No audit files found` text assertion. For an existing empty archiving group, expect its group-found and no-tables progress messages. For migration with no eligible scripts, preserve `Nothing to run` and any existing evaluation messages/warnings. Compare semantic content/severity/count while normalizing variable timestamps. Do not mock the logger in these scenarios.

## SQL, resource, and error compatibility

Use the real helper in both owner scopes with controlled command/provider boundaries. Assert text, command type, parameter names/values/types/nulls/size/precision/scale, scalar results, zero-output non-query behavior, and command disposal. Retain existing reader result shapes and model row calculations. Inject command construction, parameter validation, and execution failures and verify primary errors plus cleanup attempts.

Exercise model class paths that call SQL helpers, not merely root helper tests. Keep archiving success, partial initialization, processing, constraint restoration, cleanup-only and combined primary/cleanup failures, and interrupted/retry behavior. Audit and migration retain success/failure cleanup; migration execution errors terminate before later scripts/history writes. Preserve persisted-progress, configuration, processing-order, checksum and preview contracts. SQL Server integration supplies durability/constraint evidence that controlled providers cannot.

## Required loading and operation matrix

Each distribution runs these five scenarios in fresh workers:

| ID | Loading sequence |
|---|---|
| L1 | Clean root manifest import |
| L2 | Bootstrap required assemblies, load archiving model before root, then import root |
| L3 | Root import, then import model inside root session state after local helpers exist |
| L4 | Repeat unchanged internal imports after root import |
| L5 | Repeat forced imports on existing supported paths, without changing/redefining class source |

Include `Metadata.psm1` and `GenericSqlParam.psm1` in internal-module ownership/export checks, including normal and supported forced imports. Loading must not accidentally resolve a different source/package copy.

For each scenario run A-R-M, A-M-R, R-A-M, R-M-A, M-A-R, and M-R-A, where A is audit, R is archiving, and M is migration. This is 30 primary tuples per distribution, 60 across source/package. Each worker runs the logging combinations and representative SQL/error/cleanup checks, not just import smoke tests. Existing detailed recovery suites supplement these representative checks.

Capture root ownership before adverse imports where possible and compare after; L2 compares with the expected isolated root owner rather than an imported model owner. Inspect model-local dependencies independently. Force-import expectations permit its own refreshed module instance while prohibiting root-helper replacement.

A literal `using module` fixture checks class parsing, construction, and execution in clean processes for each distribution. Class/owner assertions and command-output assertions are independent acceptance dimensions.

## Requirement traceability

| Requirement | Design/acceptance evidence |
|---|---|
| FR-001, FR-002 | Inventory, explicit export boundary, owner and resolved-path assertions, L1–L5 |
| FR-003 | Real streams, formatting, six preference combinations, sequential invocations and no preference mutation |
| FR-004 | Existing exact-one audit regression retained and exercised in both distributions |
| FR-005 | Real archiving logger/class execution, model-local query and cleanup cases |
| FR-006, FR-007 | Three exports, full parameter metadata, supported hosts, literal class imports, unchanged parameterless APIs |
| FR-008 | Parameter/result contracts plus existing order, progress, checksums, preview, interruption/retry suites |
| FR-009 | Resource ownership, all release attempts, initialization/processing/cleanup failures, constraint restoration, primary errors |
| FR-010 | 60 source/package tuples, additional internal modules, fresh class fixtures, required SQL and host checks |

SC-001/002 require exact expected message counts/levels and zero import-induced duplicates or omissions; SC-003 requires unchanged public/configuration contracts; SC-004 requires existing operational/recovery outcomes; SC-005 requires all six same-session operation orders without a load-order workaround. Any unavailable execution checks are recorded as unverified, never passing.
