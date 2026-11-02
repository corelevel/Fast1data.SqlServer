# Data Model: Helper Ownership and Invocation Scope

This feature adds no database entity, migration, serialized configuration, or persisted logging state. The entities below describe existing runtime relationships and acceptance observations.

## Helper binding

| Field | Meaning |
|---|---|
| Name | Function name from the [inventory](research.md#dependency-inventory) |
| Source | Existing private source file |
| Owner | Root or archiving-model module session state |
| Consumers | Functions/classes that resolve this local binding |
| Export policy | Private internal helper; no accidental export into another owner |
| Identity evidence | Defining module/session-state identity and script source path |

One source definition can have multiple legitimate local owners. Root and model copies are separate bindings. Imports must not replace a root binding with a model binding. Compare defining ownership and behavior, not only source text or function name. Re-importing an unchanged model can refresh its own module instance on supported paths; it must not transfer ownership of root helpers or break existing class consumers.

## Invocation preference scope

| Field | Type/lifetime | Rule |
|---|---|---|
| Effective verbose preference | `System.Management.Automation.ActionPreference`; one invocation | Read the effective value visible to the root adapter after public common-parameter binding |
| Model execution preference | Same enum; overload method-local parameter | Name `$VerbosePreference` so nested calls use the scoped preference |
| Logger level | Existing `Verbose` or `Warning` | Retain default `Verbose`; warning is independent of verbose suppression |
| Message | Existing formatted string | Retain timestamp, level marker, message meaning, and stream |

The adapter forwards this value to the additive `TableGroup.Execute(preference)` overload. The overload delegates to existing `Execute()` and retains scope until it returns or throws. There is no module/global assignment, per-table logging property, or persisted preference. Explicit `-Verbose:$false` overrides verbose ambient state; absent override follows applicable ambient state. Warning behavior remains the existing warning policy.

Conceptual lifetime: public invocation binds common parameters → adapter captures effective preference → model overload establishes method-local scope → existing execution and nested helpers run → scope ends on success/failure. A later invocation gets its own value.

## Existing archiving execution

`TableGroup` retains identity (`Id`, `Name`), source/destination identities, `DisableFK`, connection ownership, `SourceTables`, and the hidden single-use `Started` flag. It owns many `Table` objects; tables reference their group, metadata and `ProcessState`. Keep all constructors and parameterless methods compatible.

Conceptual state transitions remain: constructed without connections → started once → initialization → preparation/archive in configured order → purge in configured order → cleanup. Failures divert to existing error/cleanup handling. All paths attempt required owned-resource release; constraint restoration and durable completion conditions stay unchanged. Retry creates a fresh group using existing persisted state. The new overload must not set `Started` or duplicate initialization/cleanup; the existing method remains the single owner.

`ProcessState` retains IDs, capture/completion dates, key bounds/checkpoints, row totals, per-batch counts, and configuration connection. This plan changes none of their validation, persistence, or transition rules. `TableColumn`, `IndexColumn`, and `Index` remain defined in `Metadata.psm1` with their current fields.

## SQL parameter and result contracts

`GenericSqlParam` retains `Value: object`, `Type: SqlDbType`, `Size: int`, `Precision: byte`, and `Scale: byte`. A query's parameter dictionary maps names to these objects. Preserve existing validation and behavior: reject other object types or missing type as currently implemented, prefix names as before, map null values to `DBNull`, and apply positive size/precision/scale settings.

A query owns its command and borrows its connection. Scalar mode returns the provider's scalar result; non-query mode emits no success output. Audit row-result shapes and archiving affected-row calculations are separate existing contracts. Do not reinterpret generic non-query results as an affected-row API.

## Error and cleanup context

A primary `ErrorRecord` can carry multiple cleanup entries in its exception chain. Preserve retrieval/deduplication and the keys `Fast1Sql.CleanupFailures` and `Fast1Archiving.CleanupFailures`. Context can include `Action`, `ResourceRole`, `GroupName`, `SourceTable`, and `ProcessStateId`, plus existing error-type/fixed-message fields. Do not add credentials, connection strings, or raw SQL to context.

If a primary error exists, cleanup annotates it without replacing it. Without a primary error, the first cleanup failure becomes terminating after remaining attempts. Readers precede commands, and owned connections follow commands; borrowed connections remain their owner's responsibility.

## Acceptance scenario record

The test worker identifies distribution root, loading scenario, operation permutation, ambient/explicit verbosity, expected message records, owner observations, and outcome. These are test inputs/results, not a new runtime class or public interface. Each distribution/loading/permutation tuple gets a fresh process; operations and sequential verbosity changes within a tuple share that process to expose contamination.
