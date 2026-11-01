# Data Model: Loader Ownership and Initialization

This feature changes code assembly only. It creates no database entity, migration, configuration field, checkpoint, or persisted-state transition. Existing SQL/workflow models remain governed by the feature 004 contract and operational documentation.

## Module consumer

| Field | Meaning | Validation |
|---|---|---|
| Identity | Root Fast1data.SqlServer or ArchivingModel | Preserve two independent behavior module session states |
| DistributionRoot | Resolved source or staged package root | Every loaded private file/module comes from the selected distribution |
| BehaviorFunctions | Functions defined by selected files | Function Module and SessionState identify the intended consumer |
| TypeDependencies | Parameter, metadata, and model declarations | Available before typed behavior is used; no changed-class hot reload requirement |
| PublicCommands | Exported operations | Three root commands; zero model helper commands |
| InitializationState | Logical loading progress | Export operations only after required initialization succeeds |

Root owns bootstrap helpers, audit/migration functions, and the archiving adapter. Model owns comparison/delay helpers and its seven existing local functions. Each owns separate instances of all eight shared functions. Type-only GenericSqlParam and Metadata modules remain existing dependencies; they add no third shared behavior service.

## Dependency selection

| Field | Meaning | Validation |
|---|---|---|
| RelativePath | Literal path resolved from its loader | No recursive private-file enumeration, exclusions, or caller working-directory dependence |
| Kind | Bootstrap, type declaration, shared behavior, component behavior | Bootstrap/type dependencies stay distinct from shared behavior list |
| OwningLoader | Root, model, shared Load, or archiving declaration Load | Ordinary behavior files perform no dependency assembly |
| Required | All selected dependencies are required | Failure terminates affected loading with safe path/stage context |
| LoadOrder | Explicit sequence | SqlClient initialization completes before shared/feature runtime assembly |

The complete file/function inventory is in [research.md](research.md). Selection is source code, not a user-configurable registry.

## Shared behavior list

The only production definition is planned at `Fast1data.SqlServer/private/shared/Load.ps1`:

| Order | File | Functions |
|---|---|---|
| 1 | GenericSqlCleanup.ps1 | Close-GenericSqlResource, Add-GenericSqlCleanupFailure, Get-GenericSqlCleanupFailure |
| 2 | GenericSqlQuery.ps1 | Get-GenericSqlCommand, Invoke-GenericSqlQuery |
| 3 | Write-LogMessage.ps1 | Write-LogMessage |
| 4 | Get-FileChecksum.ps1 | Get-FileChecksum |
| 5 | Get-RelativePath.ps1 | Get-RelativePath |

Relationship: one list is dot-sourced by two consumers, producing eight functions per consumer. There is no once-per-process guard: the second execution is required. Definitions alone produce no operational messages or database calls. Repeated supported consumer initialization follows existing module import semantics.

## Types and relationships

- GenericSqlParam remains the existing parameter descriptor: Value, Type, Size, Precision, Scale. Existing validation and parameter binding remain unchanged.
- Metadata retains TableColumn, IndexColumn, and Index.
- ArchivingModel retains TableGroup, ProcessState, and Table, their members, method overloads, and model-local command resolution.
- Root's declaration-only archiving Load imports the existing model's classes after assembly bootstrap. It defines no classes or functions itself.
- Class fixtures continue to use literal model/metadata/parameter declarations after bootstrap. Importing classes does not export model helper commands.

## Initialization transitions

Root runtime: bootstrap helper definitions → successful SqlClient initialization/reuse → shared definitions → explicit audit/migration definitions → staged model declaration → archiving adapter → public definitions and exports.

Model loading: required parameter/metadata declarations and already available SqlClient types → shared definitions in model scope → explicit delay/comparison definitions → existing local functions/classes → explicit empty helper exports.

The model declaration triggers its own runtime loading; it does not cause another root shared-loader execution. Initial root-plus-model initialization executes shared Load twice, once in each scope. If a model was already initialized through a supported path, module caching/reimport behavior follows the existing supported contract.

Any required-stage failure transitions to failed initialization: surface the error, prevent operations from proceeding with missing dependencies, and preserve caller preferences. Successful partial module state is not a recovery strategy. Repair the missing file/assembly and retry in a fresh process where class state is uncertain.

## Operational state preservation

Archive/purge state, migration history, and audit offsets are unchanged. Keep existing interruption/retry order, resource ownership, cleanup failures, verbose/warning behavior, and single-process restrictions. Validate these through the retained suites rather than introducing new persistence models.

