# Design Discussion: Export Invoke-Fast1GenericSqlQuery

**Status**: Implementation complete on 2026-11-20, including the maintainer-requested Reader rename. Source/staged offline validation and subsequent successful source live SQL acceptance are recorded in quickstart.md. The live follow-up corrected integration fixtures for delegated history cleanup, empty JSON history, and connection-string builder keys. Six baseline migration-input failures and unavailable native Linux/macOS acceptance remain explicit release limitations.

## Purpose

Expose `Invoke-Fast1GenericSqlQuery` as a public command for scalar and non-query execution. Add a separate public command that retrieves query rows through the PowerShell pipeline, plus a public factory for typed SQL parameters. Refactor `Get-Executed` to retrieve migration history through the new row command.

## Agreed decisions

Revision on 2026-11-20: the maintainer chose to revise the API instead of granting
analyzer exceptions and explicitly requested the name `Invoke-Fast1GenericSqlQueryReader`.
It continues to emit materialized row objects and owns its internal reader.
`New-Fast1GenericSqlParam` provides standard `-WhatIf`/`-Confirm`
support for descriptor creation, with low confirmation impact. Normal calls return
one descriptor; WhatIf returns none. Internal read-only history discovery explicitly
disables these factory switches so migration previews can still read history.

- Export the command as `Invoke-Fast1GenericSqlQuery`.
- Preserve `-Scalar`: return the first column of the first result row.
- Preserve the default operation: execute a non-query without emitting the affected-row count.
- Add a separate command for retrieving rows instead of adding a `-Rows` switch to `Invoke-Fast1GenericSqlQuery`.
- Name the row command `Invoke-Fast1GenericSqlQueryReader`. Give it the same `-SqlConn`, `-Query`, `-CommandType`, and `-Parameters` inputs as the existing query command, without an execution-mode switch.
- The row command emits one PowerShell object per row, with properties corresponding to SQL columns.
- Read rows incrementally through an internally managed SQL reader rather than buffering the complete result or returning a live reader to the caller.
- The function is responsible for disposing its reader and command.
- Return only the first tabular result set. Subsequent result sets are not emitted.
- Map SQL `NULL` to PowerShell `$null`; retain native types for other column values, including byte arrays for binary values.
- Reject unnamed columns and case-insensitive duplicate column names before emitting any rows. Require SQL aliases to provide usable names.
- Export `New-Fast1GenericSqlParam` so public callers can construct the existing typed parameter descriptors without importing a private module path.
- Require `-Type` on `New-Fast1GenericSqlParam`; accept optional `-Value`, `-Size`, `-Precision`, and `-Scale`. Omitting `-Value` represents SQL `NULL`.
- Accept valid SQL types including `SqlDbType.BigInt` (enum value zero), while rejecting a genuinely missing type. Correct the existing validation in support of this public contract.
- The caller supplies an already-open `-SqlConn` and remains responsible for its lifetime. The query commands leave it open.
- Reading failures terminate execution. Rows already emitted remain delivered; streaming does not promise all-or-nothing output.
- Dispose owned resources on success, failure, and early pipeline termination.
- Refactor the existing private `Get-Executed` function to use `Invoke-Fast1GenericSqlQueryReader` for migration-history reads.

## Get-Executed integration

- Retain the existing `Get-Executed -ConnStr -Phase` signature and keep the function private.
- `Get-Executed` continues to create, open, and dispose its own connection. It passes that open connection to `Invoke-Fast1GenericSqlQueryReader`, which owns the command and reader.
- Preserve the query against `dbo.fast1_migration_history` and its `phase = @phase` filter.
- Construct the phase descriptor through `New-Fast1GenericSqlParam -Type NVarChar -Size 32 -Value $Phase` and pass it through the row command's `-Parameters` hashtable.
- Stream the row command's output directly, retaining `script_name` and `checksum` as the output properties and emitting nothing when history is empty.
- Preserve persisted script-name spelling, case, and separators exactly. Migration phase evaluation continues to own identity normalization.
- Replace the local command construction, parameter binding, reader loop, and command/reader disposal with delegation to the new row command. Retain connection cleanup and primary-error preservation in `Get-Executed`.

## Public command examples

The caller imports the module and opens `$connection` before these calls, and disposes the connection afterward.

```powershell
$parameters = @{
	Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
}

# Stream objects from the first tabular result set.
Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
	-Query 'SELECT Id, Name FROM dbo.Example WHERE Id = @Id' `
	-Parameters $parameters |
	Export-Csv -Path './example.csv' -NoTypeInformation

# Preserve scalar execution.
$count = Invoke-Fast1GenericSqlQuery -SqlConn $connection `
	-Query 'SELECT COUNT(*) FROM dbo.Example' -Scalar

# Preserve silent non-query execution.
Invoke-Fast1GenericSqlQuery -SqlConn $connection `
	-Query 'UPDATE dbo.Example SET Name = NULL WHERE Id = @Id' `
	-Parameters $parameters

# A typed SQL NULL parameter.
$nullName = New-Fast1GenericSqlParam -Type NVarChar -Size 100
```

## Acceptance checks

- Importing the root module exposes all three new public commands alongside the existing public commands.
- External callers can create and use a parameter through `New-Fast1GenericSqlParam` without resolving the private class name or importing a private module path.
- Existing scalar and silent non-query callers retain their behavior.
- Row execution handles empty, single-row, and multiple-row results; an empty result emits no objects.
- A command without a tabular result emits no row objects. Only the first tabular result set is emitted when several are returned.
- Row properties retain column names and order, map SQL `NULL` to `$null`, and preserve native non-null value types, including binary arrays as individual property values.
- Empty and case-insensitively duplicate column names fail before rows are emitted, including when the result set is empty.
- The factory maps supported metadata, represents an omitted value as SQL `NULL`, and requires an explicit SQL type.
- Both query commands accept `BigInt`; genuinely missing SQL types remain invalid.
- Reader creation, row reading, and resource cleanup failures follow the existing cleanup error policy and do not dispose the borrowed connection.
- Readers and commands are released on normal completion, failure, and early pipeline termination. Previously emitted rows are retained when a later read fails.
- `Get-Executed` delegates history retrieval to `Invoke-Fast1GenericSqlQueryReader` with the correct query, open connection, and phase parameter (`NVarChar`, size `32`).
- `Get-Executed` preserves empty and populated history output, including exact stored script names and checksums, and continues to support existing migration consumers.
- The row command disposes the history reader and command before `Get-Executed` disposes its connection on success, failure, and early pipeline termination. Cleanup failures preserve the primary operation error under the existing cleanup policy.

## Scope and unchanged defaults for final review

- The new row command uses the existing command timeout behavior. No new connection-string, timeout, or transaction options are introduced by this feature.
- Internal shared helpers remain private except for the three commands explicitly named in this design.
- Implementation includes public exports, help and usage documentation, the `Get-Executed` refactor, and appropriate query, parameter, cleanup, module-loading, and migration regression verification.

## Remaining gate

Satisfied on 2026-11-20: the maintainer explicitly replied "Yes, confirm and implement" to confirmation of the complete contract. Production implementation is authorized.
