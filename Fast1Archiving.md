# Fast1 Archiving

[Back to the module README](README.md)

Fast1 Archiving incrementally archives and purges SQL Server table data. It processes rows in configurable batches, stores progress in a configuration database, and resumes incomplete work on the next run.

## Features

- Incremental archiving and purging over captured primary keys, batched by working-table positions
- Configurable key-copy, data-copy, and purge batch sizes
- Resume support for interrupted runs
- Destination schema and table creation
- Missing destination-column creation
- High-throughput transfer through `SqlBulkCopy`
- Optional foreign-key disabling during purge
- Progress and warning logging

## Requirements and limitations

- The configuration database must be on the same SQL Server instance as the source database.
- Each configured source table must have a primary key.
- The source and destination connection settings must grant the required
  metadata, DDL, read, write, and delete permissions.
- Only one process should run a given table group at a time.
- The script does NOT copy:
    - `timestamp`/`rowversion` columns
    - Computed columns
    - Indexes(except index used by primary key or clustered index)
- Missing destination columns are added automatically as `NULLABLE` columns.
- Differences in collation, nullability, and computed-column attributes produce warnings.

`DisableFK` affects inbound foreign keys on **source child tables** that reference the configured source table. Execution registers the entire scope before disabling and independently attempts to enable each constraint before releasing connections, including after partial disabling or a purge/checkpoint failure. Initially disabled constraints within that scope are also enabled under the existing policy. When `DisableFK` is off, no constraint scope is acquired or toggled.

Restoration uses `WITH NOCHECK CHECK CONSTRAINT`. A successfully restored foreign key is enabled but can remain **Not Trusted**: historical rows are not validated, invalid references can remain, and the module performs no integrity repair. Enable `DisableFK` only when you understand the purge order and accept those implications. Metadata visibility and source child-table `ALTER` permission are required in addition to normal read/delete permissions.

## Database setup

Create a configuration database, connect to it, and execute these scripts in  order:

1. [`schema/archiving/tables.sql`](Fast1data.SqlServer/schema/archiving/tables.sql)
2. [`schema/archiving/sprocs.sql`](Fast1data.SqlServer/schema/archiving/sprocs.sql)

The scripts create the configuration tables and stored procedures used by the module. Add one `dbo.TableGroup` row and one or more related `dbo.SourceTable` rows before invoking the command.

## Configuration

Each archiving job operates on a table group. A group defines the source and destination databases, their connection settings, and the source tables to process.

### `dbo.TableGroup`

| Column            | Description                                       |
| ----------------- | ------------------------------------------------- |
| `TableGroupId`    | Unique group identifier.                          |
| `Name`            | Unique name passed to `Invoke-Fast1Archiving`.    |
| `SrcServerName`   | Source SQL Server name.                           |
| `SrcDatabaseName` | Source database name.                             |
| `SrcConnOptions`  | Additional source connection-string options.      |
| `DstServerName`   | Destination SQL Server name.                      |
| `DstDatabaseName` | Destination database name.                        |
| `DstConnOptions`  | Additional destination connection-string options. |
| `DisableFK`       | Whether foreign keys are disabled during purge.   |

`SrcConnOptions` and `DstConnOptions` can contain options such as credentials, `ApplicationIntent`, `Connect Timeout`, `Encrypt`, and `TrustServerCertificate`. The module supplies the configured server and database names.

### `dbo.SourceTable`

| Column                 | Description                                                     |
| ---------------------- | --------------------------------------------------------------- |
| `SourceTableId`        | Unique source-table identifier.                                 |
| `TableGroupId`         | Parent table-group identifier.                                  |
| `SchemaName`           | Source table schema.                                            |
| `TableName`            | Source table name.                                              |
| `Active`               | Whether the configuration is active.                            |
| `DataCopyBatchSize`    | Maximum rows copied in each archive batch.                      |
| `KeyCopyBatchSize`     | Maximum keys copied in each key batch.                          |
| `PurgeBatchSize`       | Maximum rows deleted in each purge batch.                       |
| `KeyQuery`             | Query that selects only the source table's primary-key columns. |
| `Archive`              | Whether rows are copied to the destination.                     |
| `Purge`                | Whether selected rows are deleted from the source.              |
| `PurgeOrder`           | Processing order for tables enabled for purge.                  |
| `DelayInterval`        | Delay between batches in `HH:mm:ss` format.                     |
| `AlwaysRunCheck`       | Whether destination reconciliation runs for every new process.  |
| `SrcWorkingTableName`  | Computed source working-table name.                             |
| `DstWorkingTableName`  | Computed destination working-table name.                        |
| `WorkingTableKeyName`  | Computed surrogate-key column name.                             |
| `WorkingTableFlagName` | Computed reconciliation-flag column name.                       |

`KeyQuery` must return only the primary-key columns, using the same names as the source table. For example:

```sql
select OrderId
from dbo.[Order]
where OrderDate >= dateadd(day, -1, cast(getdate() as date))
	and OrderDate < cast(getdate() as date);
```

Make the selection criteria stable for the duration of a run. Rows returned by the query become the exact working set for that process.

### `dbo.ProcessState`

The module manages this table automatically.

| Column                | Description                               |
| --------------------- | ----------------------------------------- |
| `ProcessStateId`      | Unique process identifier.                |
| `SourceTableId`       | Source-table configuration identifier.    |
| `KeyCopyDate`         | Time at which key collection completed.   |
| `KeyMaxValue`         | Highest surrogate key in the working set. |
| `LastArchivedKey`     | Last archive-batch checkpoint.            |
| `RowsArchived`        | Rows copied by the process.               |
| `ArchiveCompleteDate` | Time at which archiving completed.        |
| `LastPurgedKey`       | Last purge-batch checkpoint.              |
| `RowsPurged`          | Rows deleted by the process.              |
| `PurgeCompleteDate`   | Time at which purging completed.          |
| `CompleteDate`        | Time at which all enabled work completed. |

If a run fails, leave its incomplete state and working tables intact. Running the same table group again resumes from the stored checkpoints.

## Parameters

| Parameter   | Required | Description                                                 |
| ----------- | -------- | ----------------------------------------------------------- |
| `ConnStr`   | Yes      | Connection string for the archiving configuration database. |
| `GroupName` | Yes      | Name of the configured table group to process.              |
| `LogFile`   | No       | File to which progress and warning messages are appended.   |

Detailed command help is available after importing the module:

```powershell
Get-Help Invoke-Fast1Archiving -Full
```

## Usage

```powershell
$connectionString = @(
	'Data Source=(local)'
	'Initial Catalog=fast1_archiving'
	'User ID=archiving_user'
	'Password=replace-me'
	'Encrypt=True'
	'TrustServerCertificate=True'
) -join ';'

Invoke-Fast1Archiving `
	-ConnStr $connectionString `
	-GroupName 'Orders' `
	-LogFile 'C:\Logs\fast1-archiving.log' `
	-Verbose
```

An additional executable example is available in [`example/archiving/archive-StackOverflow2013.ps1`](example/archiving/archive-StackOverflow2013.ps1).
Review its connection strings and configuration before running it.

## Failure and recovery

One invocation owns initialization, preparation, copying, purging, progress writes and cleanup. Active tables retain their supplied traversal; preparation and archiving finish before purge runs in `PurgeOrder`. Unknown groups fail; empty groups and disabled tables release their resources normally. The command has no new parameters or success object, and existing installations need no persistence or stored-procedure upgrade.

Copy, delete and checkpoint effects commit independently. No distributed transaction is introduced. A copy can commit before its checkpoint fails, and a delete can remain committed even though its saved position lags. Processing stops on a failed effect or required transition. Progress callbacks do not prove durability. Recorded row totals describe confirmed processing and can be lower than actual copied/deleted rows; retry does not reconstruct missing historical counts or promise exactly-once accounting.

After correcting the cause, retry the same group with stable configuration and one process per group. Keep the incomplete `dbo.ProcessState` row and required working tables. Once `KeyCopyDate` confirms capture, the original selected keys remain authoritative even if eligibility changes or new eligible rows arrive. Positions such as `LastArchivedKey` refer to working-table surrogate positions, including for composite or nonsequential source keys. They are not numeric source-PK boundaries.

Retry rebuilds the destination snapshot from actual presence of captured keys, independently of the current eligibility query, then resumes unfinished copying. Purge revisits retained ranges, tolerates rows already absent and never selects newly eligible outside keys. If capture was never confirmed, retry recreates and recaptures the source working set. An uncertain write response stops execution; the next invocation reloads persisted truth rather than assuming rollback. Archive completion can remain recorded while combined purge is incomplete. Required restoration precedes new purge/overall completion, and working tables are removed only after overall completion is confirmed.

Every acquired reader, command, bulk-copy object and connection receives an independent release attempt. A cleanup-only failure terminates invocation. If processing already failed, that error remains primary and cleanup failures are attached in encounter order at `Exception.Data['Fast1Archiving.CleanupFailures']`. Each entry identifies its action, group and resource or exact source constraint, with table/process identity where available and a sanitized message. For example:

```powershell
try {
	Invoke-Fast1Archiving -ConnStr $connectionString -GroupName 'Orders'
}
catch {
	$_.Exception.Data['Fast1Archiving.CleanupFailures'] | Format-List
	throw
}
```

A later drop or disposal failure can fail the invocation after completion was committed; it does not erase that completion. Failed restoration blocks new completion and identifies constraints requiring inspection. Cleanup guarantees attempts, not successful restoration during a server outage. After hard termination, inspect the exact source constraints and retained state before retry: process termination can prevent any cleanup from running. Validate or repair historical integrity separately when required.
