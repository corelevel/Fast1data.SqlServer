# Public Command Contract

**Feature**: [../spec.md](../spec.md) | **Model**: [../data-model.md](../data-model.md)

## Export surface

Both the root module export list and manifest must expose exactly:

- Invoke-Fast1Audit
- Invoke-Fast1Migration
- Invoke-Fast1Archiving
- Invoke-Fast1GenericSqlQuery
- Invoke-Fast1GenericSqlQueryReader
- New-Fast1GenericSqlParam

Existing public command metadata remains unchanged. Construction, binding, cleanup, logging, migration internals, and class modules remain private. Direct .psm1 imports and manifest imports must agree. Public factory usage requires only normal root import.

## Canonical public files

The definition and complete comment help for each new exported command reside in `Fast1data.SqlServer/public/<FunctionName>.ps1`, using exact function spelling: `Invoke-Fast1GenericSqlQuery.ps1`, `Invoke-Fast1GenericSqlQueryReader.ps1`, and `New-Fast1GenericSqlParam.ps1`. No duplicate or forwarding definition remains under `private/shared`.

This is a source layout change; the command signatures and behavior below remain unchanged. Both source and packaged imports must resolve each query's `ScriptBlock.File` to its matching public file under the selected distribution. Root and model keep independent defining scopes. See [command-loading.md](command-loading.md) for loading order, exports, and dependency failures.

## Invoke-Fast1GenericSqlQuery

```text
Invoke-Fast1GenericSqlQuery -SqlConn <SqlConnection> -Query <string>
    [-CommandType <CommandType>] [-Parameters <hashtable>] [-Scalar]
    [<CommonParameters>]
```

`SqlConn` and `Query` remain mandatory. Default CommandType is Text; StoredProcedure remains supported. Default execution calls ExecuteNonQuery and emits no affected-row count. Scalar execution returns the provider's first-column/first-row result and preserves existing empty/DBNull behavior; the row command's null conversion must not silently change scalar semantics.

Both modes construct and dispose their command, leave the caller's already-open connection open, bind typed parameters, and preserve existing timeout behavior. No Rows switch or new execution mode is added.

## Invoke-Fast1GenericSqlQueryReader

```text
Invoke-Fast1GenericSqlQueryReader -SqlConn <SqlConnection> -Query <string>
    [-CommandType <CommandType>] [-Parameters <hashtable>]
    [<CommonParameters>]
```

Inputs match the existing query command without Scalar. Each success-stream object represents one row of the first tabular result, with properties retaining SQL names, order, and native values. SQL NULL becomes PowerShell null. Binary values remain byte arrays attached to their property.

Non-tabular results preceding the first tabular result may be skipped. An empty first tabular result emits nothing and still ends result selection; later populated results are not selected. A command with no tabular result emits nothing. Do not emit provider readers, schema objects, commands, metadata, or affected-row counts.

Before reading/emitting, reject blank column names and ordinal case-insensitive duplicate names, even for empty results. Error guidance must ask for distinct SQL aliases. Preserve other names without automatic renaming or case changes.

Read and emit incrementally; do not accumulate the full result. Stop reading when the downstream pipeline stops. Previously emitted objects survive a subsequent read failure. Only the first tabular result is emitted, but later SQL statements may still execute and reader disposal may wait for pending results. There is no cancellation, rollback, or atomic-output guarantee.

## New-Fast1GenericSqlParam

```text
New-Fast1GenericSqlParam -Type <SqlDbType> [-Value <object>]
    [-Size <int>] [-Precision <byte>] [-Scale <byte>]
    [-WhatIf] [-Confirm] [<CommonParameters>]
```

Return exactly one descriptor accepted by both query commands during normal execution. The revised API supports standard WhatIf/Confirm with low confirmation impact; WhatIf returns no descriptor. Type is mandatory with no implicit BigInt default; named valid enum values and explicit BigInt/zero must work. Omitting the mandatory argument follows normal PowerShell binding/prompting behavior; explicitly supplying null or an invalid type fails binding. Private descriptors with a null Type fail executor validation.

Omitted or explicit null Value represents SQL NULL. Native values are retained, including byte arrays. Size defaults to zero and accepts nonnegative integers; Precision/Scale default to zero and use byte ranges. Positive metadata is forwarded as in the existing binder; zero retains provider defaults. In particular, Scale zero does not force decimal scale zero. MAX size -1, direction/output parameters, and extra type metadata are outside this contract.

No connection is allocated and no SQL runs when creating a descriptor. Callers do not need `using module`, a private module path, or the private class name.

## Parameter binding

Parameters is an optional hashtable keyed by name without `@`. Every value must be a descriptor of the existing class. Bind explicitly with SqlDbType, never inferred AddWithValue. Reject missing Type by null comparison, not truthiness; BigInt zero is valid. Convert null to DBNull.Value with direct value assignment and preserve native non-null values.

The internal shared binding function emits no success output and remains in `private/shared/GenericSqlQuery.ps1` alongside the private command factory. Both root and archiving model use their locally defined support functions and independently loaded public query definitions; nested modules export no commands.

## Resource and error policy

| Condition | Required behavior |
|---|---|
| Success | Dispose reader if created, then command; leave borrowed connection open. |
| Construction, binding, reader creation, schema, or read error | Terminate, attempt all owned disposal, preserve primary error. |
| Failure after rows were emitted | Prior rows remain delivered; terminate further delivery. |
| Reader or command disposal failure | Attempt remaining disposal; attach existing safe cleanup details. Throw first cleanup error if no primary operation error exists. |
| Early downstream termination | Release reader and command; do not drain rows through the application loop or dispose the connection. |
| Closed/invalid borrowed connection | Surface the provider/binding failure; do not open or repair the connection. |

Do not log credential-bearing connection strings or add SQL/value data to cleanup annotations. Errors continue to use existing PowerShell/provider conventions; this feature does not introduce a new public error-code taxonomy.

PowerShell can suppress a cleanup exception thrown while a downstream command is stopping upstream execution. The cleanup helper still attempts every owned disposal and throws with the existing safe details; an outer catch may not observe that throw during pipeline truncation.

## Help and validation

Retain complete comment help and runnable README examples for connection ownership, typed nulls, parameters, scalar/non-query behavior, aliases, first-result streaming, partial errors, and metadata limits. Move help together with its query definition. Update affected source-location and loader guidance; preserve the existing six-command release contract and runtime/dependency versions. See [../quickstart.md](../quickstart.md) for source, staged, offline, and live validation.
