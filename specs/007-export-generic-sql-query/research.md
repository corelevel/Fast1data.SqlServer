# Research: Export Generic SQL Commands

**Date**: 2026-11-20 | **Feature**: [spec.md](spec.md)

Research used current repository code, two delegated read-only investigations, official documentation, and isolated PowerShell 7.6.10 probes. No production code was changed or live SQL acceptance run. All design unknowns are resolved; implementation validation remains separate.

Implementation revision: the maintainer requested Invoke-Fast1GenericSqlQueryReader and chose API revision instead of analyzer exceptions. The factory now supports standard WhatIf/Confirm; internal history discovery explicitly opts out for its in-memory descriptor. Deterministic truncation probes also showed that the PowerShell engine can suppress a cleanup throw during upstream stopping; the helper still attempts all resources and throws with safe details. See the updated contract and quickstart for accepted behavior and actual validation.

## 1. Public surface and shared module boundaries

**Decision**: Keep both query implementations and a private parameter-binding helper in `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`. Add the descriptor factory in `public/New-Fast1GenericSqlParam.ps1`. Root exports its public-file basenames plus the two shared query names; the manifest explicitly lists all six public functions.

**Rationale**: Root and `ArchivingModel.psm1` independently dot-source `private/shared/Load.ps1`. Keeping the existing query definition there preserves each consumer's defining session state. The factory needs the root's existing class import, not an exported type module. Private helper visibility must not expand incidentally.

**Alternatives considered**: Moving the existing query into root-only public files breaks the model's independent shared behavior. Replacing it with a same-name forwarding wrapper risks resolution/ownership changes. Exporting every shared function exposes cleanup and construction internals. Defining the factory in shared behavior is possible but adds an unnecessary model-local function.

**Repository evidence**: `Fast1data.SqlServer.psm1`, `Fast1data.SqlServer.psd1`, `private/shared/Load.ps1`, `private/archiving/ArchivingModel.psm1`, and `tests/fixtures/SharedHelpers.Scenarios.ps1`, all under `Fast1data.SqlServer/`.

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
