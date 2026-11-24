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

## Tests

All suites in `Fast1data.SqlServer/tests` end in `.Tests.ps1`. Files containing
`.Integration.` require live SQL Server or audit resources; platform-specific
suites include `.Linux.` or `.Windows.` before the suffix.

Run the suites that do not require live services from the repository root:

```powershell
$testPaths = Get-ChildItem ./Fast1data.SqlServer/tests/*.Tests.ps1 |
	Where-Object Name -NotLike '*.Integration.*' |
	Select-Object -ExpandProperty FullName
Invoke-Pester -Path $testPaths -Output Detailed
```

Migration command tests are in `Migration.Tests.ps1`, phase validation is in
`Migration.Phase.Tests.ps1`, and live SQL cases are in
`Migration.Integration.Tests.ps1`.
Factory, row/schema/native-value tests live in `GenericSqlQuery.Tests.ps1`;
streaming and failure ownership cases run through `SqlCleanup.Tests.ps1` and its
controlled fixtures. Real provider acceptance is in `GenericSqlQuery.Integration.Tests.ps1`.

### Live integration tests

Set the variables required by the selected suite in the PowerShell session before
calling Pester. Child PowerShell processes inherit these environment variables.

| Environment variable | Used by | Value |
| --- | --- | --- |
| `FAST1_TEST_MIGRATION_SQL_CONN_STR` | Migration and generic SQL queries | SQL Server connection string for a disposable test instance |
| `FAST1_TEST_ARCHIVING_SQL_CONN_STR` | Archiving | SQL Server connection string for a disposable test instance |
| `FAST1_TEST_AUDIT_SQL_CONN_STR` | Audit on Windows and Linux | SQL Server connection string for a disposable test instance |
| `FAST1_TEST_AUDIT_FOLDER` | Audit on Windows and Linux | Folder containing closed, immutable, nonempty `.sqlaudit` files |
| `FAST1_TEST_AUDIT_SMB_USER` | Audit on Linux | SMB user name with access to the audit share |
| `FAST1_TEST_AUDIT_SMB_PASSWORD` | Audit on Linux | SMB user password |

For example, configure migration tests and run them from the repository root:

```powershell
$env:FAST1_TEST_MIGRATION_SQL_CONN_STR = 'Server=YOUR_TEST_SERVER;Initial Catalog=master;Integrated Security=True;Encrypt=True'
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1 -Output Detailed
```

Use the authentication and encryption options required by your test environment.
Supply credentials locally or through your CI secret store. The SQL login needs
permission to create/drop test databases and create/execute the suite's fixtures.
The suites create uniquely named databases and attempt to drop them during cleanup.

Migration and generic SQL query integration skip when their connection variable is missing or blank. Archiving and
the audit suite for the current operating system fail setup if required variables
are missing. Audit suites skip on other operating systems. Windows audit discovery
uses the current Windows identity; Linux requires `smbclient` and a backslash UNC
folder accessible to both the SMB account and SQL Server service.

See [migration](Fast1Migration.md#live-integration-tests),
[archiving](Fast1Archiving.md#tests), and [audit](Fast1Audit.md#live-integration-tests)
for suite-specific commands and prerequisites.

## License

This project is licensed under the [MIT License](LICENSE).
