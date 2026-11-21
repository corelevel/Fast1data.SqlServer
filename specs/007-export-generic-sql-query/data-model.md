# Data Model: Generic SQL Commands

**Feature**: [spec.md](spec.md) | **Public contract**: [contracts/public-commands.md](contracts/public-commands.md)

The original feature adds in-memory command/row objects. The public-file relocation changes no fields, persisted schemas, configuration, or lifecycle semantics. It changes the source ownership described below.

## Command source and consumer scope

| Command | Canonical source under `Fast1data.SqlServer/` | Defining consumer scopes |
| --- | --- | --- |
| `Invoke-Fast1GenericSqlQuery` | `public/Invoke-Fast1GenericSqlQuery.ps1` | Root module and archiving model, independently dot-sourced |
| `Invoke-Fast1GenericSqlQueryReader` | `public/Invoke-Fast1GenericSqlQueryReader.ps1` | Root module and archiving model, independently dot-sourced |
| `New-Fast1GenericSqlParam` | `public/New-Fast1GenericSqlParam.ps1` | Root module only, unchanged |

Each filename stem matches its top-level public function name and contains its help. Neither query definition remains in the private shared directory. Two runtime function instances from one source file are expected; their defining Module and SessionState remain distinct. The factory and both consumers retain their existing descriptor class imports, with no second descriptor type.

Private `GenericSqlQuery.ps1` retains only the binder and command factory. Each consumer loads private support before its query definitions. Root loads public files through its existing discovery loop; the model selects only the two query public files explicitly and exports neither. See [contracts/command-loading.md](contracts/command-loading.md) for initialization and failure contracts.

## Typed parameter descriptor

The public factory returns the existing private `GenericSqlParam` class; public callers treat the result as a descriptor without importing that class.

| Field | Representation | Default | Rule |
|---|---|---|---|
| Type | Nullable System.Data.SqlDbType | null for uninitialized private descriptor | Required by factory; null rejected by both executors; BigInt/zero accepted. |
| Value | object | null | Null binds to DBNull.Value; other values retain native representation, including byte arrays. |
| Size | int | 0 | New factory accepts 0 through Int32.MaxValue; only positive values are forwarded. |
| Precision | byte | 0 | Positive values forwarded; zero leaves provider default. |
| Scale | byte | 0 | Positive values forwarded; zero leaves provider default, including inference. |

Existing internal cast-hashtable construction remains supported. Changing the private Type property to nullable deliberately changes its reflection contract. No nullable metadata/presence fields, parameter direction, TypeName, output value retrieval, or MAX size control is introduced.

Factory creation follows standard ShouldProcess semantics: normally one descriptor, no descriptor under WhatIf, low confirmation impact. This adds no fields or SQL resources.

## Parameter collection

`Parameters` is a hashtable from SQL parameter name to descriptor. Keys omit the leading `@`; binding creates the provider parameter name. Both query commands use the same validation and binding routine. A wrong descriptor or missing type terminates before execution. The collection and descriptors stay caller-owned; commands own the created provider parameters. No inferred AddWithValue binding is added.

## Command invocation

| Field | Representation | Ownership or behavior |
|---|---|---|
| SqlConn | Microsoft.Data.SqlClient.SqlConnection | Borrowed, already open; never opened, closed, or disposed by query commands. |
| Query | string | Mandatory SQL text or procedure name; executable administrator input. |
| CommandType | System.Data.CommandType | Text by default; existing StoredProcedure usage retained. |
| Parameters | hashtable | Optional typed descriptors. |
| Scalar | switch, existing command only | First-column/first-row provider result; absent means silent non-query. |

The command is newly constructed and owned by its query function. Preserve the existing provider timeout and execution defaults. No transaction object or connection-string input is added.

## First-result schema

A transient list of `(ordinal, name)` entries is built for the first result with `FieldCount > 0`. Names must be nonblank and unique with ordinal case-insensitive comparison. Preserve accepted names exactly and in SQL column order. Validate before reading any row, including when the result contains zero rows.

## Row object

A fresh ordered `PSCustomObject` contains one property per schema entry. `GetValue(ordinal)` supplies native values; only `DBNull` becomes PowerShell null. A binary array remains a single property value, including lengths zero and one. Row objects have no reader/command reference and remain usable after cleanup. Empty results emit zero objects; there is no placeholder or count output.

## Migration history row

Existing persisted fields remain unchanged:

| Field | SQL representation | Output rule |
|---|---|---|
| phase | nvarchar(32) | Bound filter, not an output property. |
| script_name | Existing history column | Preserve exact stored spelling/case/separators. |
| checksum | Existing history column | Return unchanged after script_name. |

`Get-Executed` produces the same row shape through delegation; it retains its private `-ConnStr -Phase` contract. Schema ownership remains with existing migration setup scripts.

## Execution and lifetime transitions

1. Validate/bind inputs while constructing the owned command.
2. Existing command executes scalar or non-query; row command creates its owned reader.
3. Row path seeks the first tabular result, validates schema, then alternates read/materialize/emit. It stops at that result's end or downstream pipeline termination.
4. On operation error, retain the primary error and terminate. Already emitted rows remain observable.
5. Always attempt reader disposal before command disposal, without disposing the borrowed connection.
6. For history calls, outer connection disposal follows inner row-command cleanup, including errors and downstream truncation.

Cleanup failures append safe details under the existing `Fast1Sql.CleanupFailures` exception-data key. Preserve a primary operation error; if none exists, the first cleanup error becomes terminating after all disposals are attempted. No completion marker, rollback, or all-or-nothing row delivery is implied.
