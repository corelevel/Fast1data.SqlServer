# Research: Export Generic SQL Commands

**Date**: 2026-11-20 | **Feature**: [spec.md](spec.md)

The relocation amendment was researched through two delegated read-only repository investigations: command loading and affected validation. No new external API or dependency behavior is assumed, so the amendment is resolved from the actual loaders and fixtures. No production code or runtime checks were run during this planning revision. All design unknowns are resolved; relocation validation remains pending. Earlier sections retain the original provider research and its sources; historical implementation results are in quickstart.md.

Implementation revision: the maintainer requested Invoke-Fast1GenericSqlQueryReader and chose API revision instead of analyzer exceptions. The factory now supports standard WhatIf/Confirm; internal history discovery explicitly opts out for its in-memory descriptor. Deterministic truncation probes also showed that the PowerShell engine can suppress a cleanup throw during upstream stopping; the helper still attempts all resources and throws with safe details. See the updated contract and quickstart for accepted behavior and actual validation.

## 1. Public surface and shared module boundaries

**Decision**: Put each query implementation and its complete help in its matching `public/Invoke-Fast1GenericSqlQuery.ps1` or `public/Invoke-Fast1GenericSqlQueryReader.ps1`. Keep `New-Fast1GenericSqlParam` in its existing matching public file. Retain only `Add-GenericSqlParameter` and `Get-GenericSqlCommand` in the private shared query file. Root's existing public-file loop loads each definition and exports public basenames without appended query names; the manifest retains its six explicit names. The model explicitly dot-sources the two public query files immediately after shared support, inside its existing dependency error boundary.

**Rationale**: FR-001 and FR-002 supersede the preceding decision to keep public definitions in the shared file. Dot-sourcing the same canonical public files into each consumer preserves independent defining session states without duplicate source implementations. Shared support still loads first in each scope; the existing descriptor class imports remain in place. Public location does not require model exports. Root loads the archiving model before its public discovery stage, so a missing required query file must fail root initialization through the model's mandatory dependency load as well as fail standalone model initialization.

**Alternatives considered**: Root-only relocation loses model-local command resolution. Public forwarding wrappers do not move the implementations as requested. Loading public files from the shared list and again through root public discovery unnecessarily redefines them. Copying implementations or introducing a behavior module complicates ownership and type identity. Renaming the private support file is unrelated to the explicit exported-function naming requirement. No new generic loader or independent required-file registry is needed; existing root/model dependency boundaries can enforce the two required query files, verified by fault injection.

**Repository evidence**: `Fast1data.SqlServer.psm1`, `Fast1data.SqlServer.psd1`, `private/shared/Load.ps1`, `private/archiving/ArchivingModel.psm1`, and `tests/fixtures/SharedHelpers.Scenarios.ps1`, all under `Fast1data.SqlServer/`.

## 1a. Relocation validation and packaging

**Decision**: Preserve the 23-file private inventory, three-entry shared loader, six-command metadata snapshot, and 16 independent function-owner observations. Verify the model's two public file references separately from private inventory coverage. Add AST checks for matching public definitions/help and absence of those definitions under `private/shared`; strengthen runtime provenance to exact public `ScriptBlock.File` paths. Exercise missing, corrupt, and runtime-failing public query files in root and standalone model consumers.

**Rationale**: `tests/ModuleLoaders.Tests.ps1` currently combines selected dependency paths with the private inventory; adding public references must not falsely inflate that private count to 25. `tests/fixtures/Invoke-ModuleLoaderScenario.ps1` and `SharedHelpers.Scenarios.ps1` already require eight functions independently defined in each consumer, and relocation does not change that contract. The six-command snapshot records signatures rather than source paths and needs no regeneration. `out/publish.ps1 -StageOnly` copies the public/private/test trees and runtime assets but does not run tests, so staged suites must be invoked separately.

**Alternatives considered**: Loosening inventory/ownership assertions hides missing files or scope regressions. Regenerating metadata snapshots would obscure an unintended signature change. Source imports alone do not establish package completeness. A new packaging mechanism is unnecessary.

**Verification boundary**: Existing query, cleanup, history, archiving execution, loader, and 30-scenario import matrix coverage remains applicable. The shared worker currently expects 249 cases; recalculate only when its included suites gain cases. The six known migration-input failures and platform-specific Windows skip remain historical baseline information, not amendment results. Re-run real provider/history suites against the explicitly selected test SQL environment; record unavailable native hosts and all skips separately.

**Repository evidence**: `tests/ModuleLoaders.Tests.ps1`, `tests/SharedHelpers.Import.Tests.ps1`, `tests/Archiving.Execution.Tests.ps1`, `tests/fixtures/Invoke-ModuleLoaderScenario.ps1`, `tests/fixtures/Invoke-SharedHelperScenario.ps1`, `tests/fixtures/SharedHelpers.Scenarios.ps1`, and `out/publish.ps1`.

## 2. Missing SQL type versus BigInt zero

**Decision**: Change descriptor `Type` from `SqlDbType` to nullable `SqlDbType`. Require a typed mandatory `-Type` on the public factory and explicitly reject a null descriptor type in the shared binder.

**Rationale**: The current nonnullable enum defaults to zero. Consequently a newly constructed descriptor and an explicitly assigned BigInt are indistinguishable, and the current truthiness check rejects both. A local nullable-property probe distinguished missing/null from explicit zero while preserving named enum and cast-hashtable assignments. Update the intentional private reflection assertion in `tests/SqlCleanup.Tests.ps1`; retain existing internal descriptor construction.

**Alternatives considered**: Removing validation accepts genuinely omitted types. A special invalid enum sentinel needs a hidden convention and additional checks. Adding an explicit-type flag cannot reliably track existing public property assignments. Nullable type states the invariant directly.

**Source**: [SqlDbType enum](https://learn.microsoft.com/en-us/dotnet/api/system.data.sqldbtype?view=net-10.0). BigInt has value zero; enum truthiness is not presence.

## 3. Parameter metadata and native parameter values

**Decision**: Return the existing descriptor with `Value`, `Type`, `Size`, `Precision`, and `Scale`. Omitted value remains null and binds to `DBNull.Value`. Preserve existing positive-only metadata forwarding: zero/omitted metadata leave provider defaults. The new factory validates Size as nonnegative; MAX size `-1`, output parameters, and explicit decimal zero-scale control are outside this feature.

**Rationale**: The specification exposes the existing descriptor, and the binder already applies only positive metadata. Retaining that behavior avoids introducing metadata-presence tracking or altering existing callers' numeric inference. The factory and binder must assign native values directly, with separate null handling, so binary arrays stay arrays.

**Alternatives considered**: Nullable metadata/presence tracking would allow additional controls but expands this public contract. Inferring SQL types from values conflicts with mandatory explicit types and typed nulls.

**Sources**: [Configure parameters](https://learn.microsoft.com/en-us/sql/connect/ado-net/configure-parameters?view=sql-server-ver17), [SqlParameter.Size](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlparameter.size?view=sqlclient-dotnet-7.1). The limited forwarding policy is a compatibility decision from repository code, not a claim that the provider cannot support other values.

## 4. First tabular result and incremental output

**Decision**: Call default `ExecuteReader()`; while `FieldCount` is zero, advance with `NextResult()` until a tabular result exists or results end. Once columns exist, select that result even if it is empty, and never advance to another tabular result.

**Rationale**: Result metadata identifies a tabular result independently of row count. Emit one freshly materialized row before attempting the next read. This bounds application buffering to metadata plus one row; it does not promise streaming individual large fields.

**Alternatives considered**: `HasRows` would skip the first empty tabular result. `DataTable.Load`, an accumulated list, and collecting pipeline output internally buffer the result. Returning a reader transfers resource ownership contrary to the spec.

**Sources**: [FieldCount](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqldatareader.fieldcount?view=sqlclient-dotnet-7.1), [NextResult](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqldatareader.nextresult?view=sqlclient-dotnet-core-6.1).

## 5. Column validation and row representation

**Decision**: Cache names in ordinal order; reject null/empty/whitespace-only names and duplicates using ordinal case-insensitive comparison before the first `Read()`. Preserve valid names exactly. Build an ordered property dictionary and emit one `PSCustomObject` per row.

**Rationale**: Metadata validation also runs for empty results. Early validation avoids ambiguous properties and any output before a schema error. Ordinal access preserves column ordering and avoids name lookup ambiguity.

**Alternatives considered**: Automatic aliases silently change the SQL contract. Validation while reading misses empty result sets. Case-sensitive validation permits names PowerShell cannot reliably distinguish.

**Source**: [SqlDataReader API](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqldatareader?view=sqlclient-dotnet-7.1).

## 6. SQL NULL and binary array preservation

**Decision**: Assign `GetValue(ordinal)` directly to a variable, separately replace `DBNull` with null, then assign the property. Do not stringify values or route binary values through an output-producing conditional expression.

**Rationale**: A local DataTableReader probe on PowerShell 7.6.10 showed that direct assignment preserves `System.Byte[]`, whereas collecting an `if` expression enumerates it, producing an object array or collapsing zero/one-element arrays. The existing parameter binder has the same expression pattern, so fix native-value assignment there when extracting it.

**Alternatives considered**: String formatting loses provider types; array wrappers around every value change scalar properties. Use ordinary assignments instead.

**Source**: [GetValue](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqldatareader.getvalue?view=sqlclient-dotnet-7.1). Verify zero-, one-, and multi-byte arrays for rows and parameter values.

## 7. Resource lifetime, partial failures, and pipeline truncation

**Decision**: Reuse the operation-error/`finally` pattern and `Close-GenericSqlResource` with reader then command. Never use `CommandBehavior.CloseConnection`. Keep `Get-Executed`'s outer owned connection cleanup.

**Rationale**: Existing helpers attempt all disposals and preserve the operation error with safe cleanup annotations; cleanup-only failure throws after attempts. A local nested-function probe confirmed `finally` and cleanup helper execution under `Select-Object -First 1`; ordinary truncation did not enter `catch`. Explicit regression coverage remains necessary for the real implementation and nested history path.

**Alternatives considered**: Caller disposal of a returned reader violates ownership. Adding a new cleanup framework or advanced-function lifecycle blocks is unnecessary for resources allocated within one execution block.

**Sources**: [PowerShell try/catch/finally](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally?view=powershell-7.6), [CommandBehavior](https://learn.microsoft.com/en-us/dotnet/api/system.data.commandbehavior?view=net-10.0). Repository policy: `Fast1data.SqlServer/private/shared/GenericSqlCleanup.ps1`.

## 8. Later results and disposal latency

**Decision**: Define first-result-only as emitted output. Do not promise cancellation, SQL rollback, or immediate disposal. Do not add automatic `Cancel()`.

**Rationale**: Disposing/closing a reader can consume pending results, and later statements may execute without their row sets being emitted. A later provider or cleanup error must still surface; previously delivered rows remain delivered.

**Alternatives considered**: Automatic cancellation changes server execution behavior and adds a new failure policy beyond the requested feature.

**Source**: [SqlDataReader.Close](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqldatareader.close?view=sqlclient-dotnet-7.1).

## 9. History integration and verification boundaries

**Decision**: `Get-Executed -ConnStr -Phase` opens its connection, creates the NVarChar(32) phase descriptor through the factory, streams the row command's unchanged history SELECT, and disposes only its connection. Preserve original script-name spelling, case, separators, and checksum.

**Rationale**: `Resolve-MigrationPhase` owns identity normalization; history reads must retain original keys for forced updates. Existing cleanup tests expect three directly owned resources and must change to connection-only ownership plus nested disposal-order verification.

**Alternatives considered**: Normalizing history keys here breaks exact persisted-key handling. Capturing all row output before returning breaks streaming.

**Validation decision**: Use controlled readers to prove read timing and injected errors, and SQL Server to prove actual metadata/result-set/null/type/procedure behavior. Reuse the opt-in `FAST1_TEST_MIGRATION_SQL_CONN_STR` test environment for the new live query suite, creating its own unique disposable database. Retain migration force/retry/preview regressions and shared-owner/import/package tests. Update export snapshots deliberately while preserving original command metadata; recalculate worker totals only when test counts change.
