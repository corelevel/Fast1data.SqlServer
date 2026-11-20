# Private Migration History Integration Contract

**Feature**: [../spec.md](../spec.md) | **Public row contract**: [public-commands.md](public-commands.md)

## Signature and SQL

Retain private `Get-Executed -ConnStr <string> -Phase <string>`. Both arguments remain mandatory. Preserve the existing SQL:

```sql
set nocount on
select script_name, [checksum]
from dbo.fast1_migration_history
where phase = @phase
```

Get-Executed creates, initializes, and opens its own connection. It creates the phase descriptor through `New-Fast1GenericSqlParam -Type NVarChar -Size 32 -Value $Phase -WhatIf:$false -Confirm:$false` and delegates the SELECT with `Parameters = @{ phase = <descriptor> }`, Text command type, and its open connection to Invoke-Fast1GenericSqlQueryReader.

No direct command construction, parameter binding, reader loop, or command/reader disposal remains in Get-Executed. Stream the delegated result directly without array collection, projection, or key normalization.

## Output and identity

Return zero or more row objects with script_name and checksum in that order. Empty history emits nothing. Preserve checksums and persisted names exactly, including original case, spelling, and slash/backslash separators. Resolve-MigrationPhase continues to own identity normalization; forced updates must retain access to original persisted keys.

No history write, execution timestamp, schema, phase ordering, checksum, ignore/force, retry, or preview contract changes.

## Ownership and failures

The row command owns reader then command cleanup. Get-Executed owns only connection cleanup, performed after the delegated command unwinds. Preserve that order on success, reader creation/schema/read failures, downstream truncation, and cleanup failures.

Get-Executed retains its operation-error capture and rethrow. Attach connection cleanup failures to an existing primary error without replacing it. Inner reader/command cleanup details must remain discoverable alongside outer connection details through the existing cleanup helper.

If inner cleanup fails without an operation error, that cleanup error becomes the outer primary error; connection cleanup is still attempted. Connection construction/open failure must also attempt cleanup of any created connection. Do not add connection strings or SQL values to cleanup metadata.

## Required verification

Prove delegation with the exact query/filter, correct open connection, and NVarChar/32 phase metadata. Prove empty/populated output and exact legacy names. Verify nested reader-command-connection disposal, partial output after a later read failure, connection-open failure, and combined cleanup failure preservation.

Retain the full migration regression coverage for phase identity, case/separator behavior, original-key forced updates, checksums, skipped timestamps, idempotent retry, and WhatIf. Use the live history suite for persisted behavior; do not treat mocks as proof of SQL Server collation/metadata behavior.
