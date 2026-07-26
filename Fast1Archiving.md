# Fast1 Archiving

[Back to the module README](README.md)

Fast1 Archiving incrementally archives and purges SQL Server table data. It processes rows in configurable batches, stores progress in a configuration database, and resumes incomplete work on the next run.

## Features

- Incremental archiving and purging based on primary-key ranges
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

Disabling foreign keys during a purge can result in invalid data. Enable `DisableFK` only when the purge order and referential integrity implications are fully understood, and you accept the possibility of leaving foreign keys or check constraints in a **Not Trusted** state in the archiving database.

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
