# Fast1data.SqlServer

Fast1data.SqlServer is a PowerShell module for SQL Server administration and deployment workflows. It currently provides:

- [Fast1 Audit](Fast1Audit.md) — resumable import of [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine) (`.sqlaudit`) files into a SQL Server database.
- [Fast1 Migration](Fast1Migration.md) — ordered, checksum-protected execution of SQL Server migration scripts.
- [Fast1 Archiving](Fast1Archiving.md) — resumable, batch-based archiving and purging between SQL Server databases.
- [Generic SQL commands](#generic-sql-commands) — `Invoke-Fast1GenericSqlQuery` for scalar values and non-query commands, `Invoke-Fast1GenericSqlQueryReader` for streaming rows, and `New-Fast1GenericSqlParam` for typed input parameters.

## Requirements

- PowerShell 7.6 or later (Core)
- An x64 Windows or x64 Linux runtime, with both OS and PowerShell process reporting X64
- Network and database permissions required by the selected feature

The module bundles `Microsoft.Data.SqlClient 7.1.2`, `Microsoft.SqlServer.TransactSql.ScriptDom 180.154.0`,
and their required native/resource dependencies for these runtime identifiers:

- `win-x64`
- `linux-x64`

See [migration authoring and recovery guidance](Fast1Migration.md) for supported
T-SQL batches, unsupported SQLCMD syntax, and idempotent retries after partial failures.

## Install from PowerShell Gallery

- Simply run
```powershell
Install-Module -Name Fast1data.SqlServer
```

## Install from source

- Clone the repository
- With a .NET SDK supporting `net10.0` installed, build the bundled client/parser libraries if `lib` is not already populated:
```powershell
.\build\build.ps1
```
- Import the module directly from the repository:
```powershell
Import-Module .\Fast1data.SqlServer\Fast1data.SqlServer.psd1 -Force
```
- Confirm that the public commands are available:
```powershell
Get-Command -Module Fast1data.SqlServer
```

## Features

### SQL Server Audit import

Use `Invoke-Fast1Audit` to discover audit files, import new records, and resume from stored file offsets.

See [Fast1Audit.md](Fast1Audit.md) for database setup, permissions, ignore rules, and usage.

### SQL Server migrations

Use `Invoke-Fast1Migration` to execute scripts in configured order, record their checksums, preview changes with `-WhatIf`, and selectively ignore or force scripts.

See [Fast1Migration.md](Fast1Migration.md) for schema setup, configuration, execution behavior, and CI/CD examples.

### SQL Server archiving

Use `Invoke-Fast1Archiving` to copy and optionally purge configured table data in resumable batches.

See [Fast1Archiving.md](Fast1Archiving.md) for prerequisites, database setup, table-group configuration, limitations, and usage.

### Generic SQL commands

Use these three functions to run parameterized SQL on an open `Microsoft.Data.SqlClient.SqlConnection`:

| Function | Use it to |
| --- | --- |
| `Invoke-Fast1GenericSqlQuery` | Execute a command without output, or add `-Scalar` to return the first column of the first row. |
| `Invoke-Fast1GenericSqlQueryReader` | Stream result rows as PowerShell objects for filtering, processing, or export. |
| `New-Fast1GenericSqlParam` | Create a typed input parameter for either query function. |

Pass parameters in a hashtable with names **without** `@`; use `@` in the SQL text.
Specify each parameter's SQL type with `-Type`, and use `-Size`, `-Precision`, or
`-Scale` when needed. Omitting `-Value` or passing `$null` creates a typed SQL NULL.

The following example creates parameters, reads rows, retrieves a scalar, and
updates data. Open the connection before calling the query functions and dispose
it when finished; both functions leave it open.

```powershell
Import-Module Fast1data.SqlServer
# Supply the connection string locally or through your secret store.
$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($env:MY_SQL_CONNECTION_STRING)
try {
	$connection.Open()
	$parameters = @{
		Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
		Name = New-Fast1GenericSqlParam -Type NVarChar -Size 100 -Value 'Example'
	}

	# Read rows as objects and export them to CSV.
	Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
		-Query 'SELECT Id, Name FROM dbo.Example WHERE Id = @Id' `
		-Parameters @{ Id = $parameters.Id } |
		Export-Csv ./example.csv -NoTypeInformation

	# Return a single value.
	$count = Invoke-Fast1GenericSqlQuery -SqlConn $connection `
		-Query 'SELECT COUNT(*) FROM dbo.Example' -Scalar

	# Execute an update without returning an affected-row count.
	Invoke-Fast1GenericSqlQuery -SqlConn $connection `
		-Query 'UPDATE dbo.Example SET Name = @Name WHERE Id = @Id' -Parameters $parameters
}
finally {
	$connection.Dispose()
}
```

For stored procedures, pass the procedure name to `-Query` and add
`-CommandType StoredProcedure` to either query function.

`Invoke-Fast1GenericSqlQueryReader` returns rows from the first result set with
columns, preserving column order and native values and converting SQL NULL to
PowerShell `$null`. An empty first result set produces no rows; later result sets
are ignored. Column names must be nonblank and unique, ignoring case; use SQL
aliases where needed. Rows arrive incrementally, so rows already delivered remain
available if a later read fails. Stopping the pipeline does not guarantee SQL
cancellation or rollback.

`New-Fast1GenericSqlParam` preserves native input values, including byte arrays.
Only positive size, precision, and scale values override provider defaults; a
scale of `0` leaves scale inference to the provider. Size `-1` (`MAX`) and output
parameters are unsupported. See `Get-Help <function-name> -Full` for full details.

## Help

PowerShell command help is available after importing the module:

```powershell
Get-Help Invoke-Fast1Audit -Full
Get-Help Invoke-Fast1Migration -Full
Get-Help Invoke-Fast1Archiving -Full
Get-Help Invoke-Fast1GenericSqlQuery -Full
Get-Help Invoke-Fast1GenericSqlQueryReader -Full
Get-Help New-Fast1GenericSqlParam -Full
```

## License

This project is licensed under the [MIT License](LICENSE).
