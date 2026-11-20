# Fast1data.SqlServer

Fast1data.SqlServer is a PowerShell module for SQL Server administration and deployment workflows. It currently provides:

- [Fast1 Audit](Fast1Audit.md) — resumable import of [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine) (`.sqlaudit`) files into a SQL Server database.
- [Fast1 Migration](Fast1Migration.md) — ordered, checksum-protected execution of SQL Server migration scripts.
- [Fast1 Archiving](Fast1Archiving.md) — resumable, batch-based archiving and purging between SQL Server databases.
- Typed scalar, silent non-query, and streaming row commands for caller-owned SQL connections.

## Requirements

- PowerShell 7.6 or later
- No separate SqlServer PowerShell module installation is required.
- An x64 Windows, Linux, or macOS runtime
- Network and database permissions required by the selected feature

The module bundles `Microsoft.Data.SqlClient`, `Microsoft.SqlServer.TransactSql.ScriptDom`,
and their required native/resource dependencies for these runtime identifiers:

- `win-x64`
- `linux-x64`
- `osx-x64`

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

The root module exports exactly `Invoke-Fast1Audit`, `Invoke-Fast1Migration`,
`Invoke-Fast1Archiving`, `Invoke-Fast1GenericSqlQuery`, `Invoke-Fast1GenericSqlQueryReader`, and
`New-Fast1GenericSqlParam`. Both manifest and direct `.psm1` imports support this surface.
No private class import or `using module` is needed by callers.

Open the connection before querying and dispose it afterward. Query commands own
their commands and readers and leave your connection open. SQL text and procedure
names are executable administrator inputs. Existing command timeout defaults apply.

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1
# Supply the connection string locally or through your secret store.
$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($env:MY_SQL_CONNECTION_STRING)
try {
	$connection.Open()
	$parameters = @{
		Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
		Name = New-Fast1GenericSqlParam -Type NVarChar -Size 100 # Typed SQL NULL
	}
	Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
		-Query 'SELECT @Id AS Id, @Name AS Name' -Parameters $parameters |
		Export-Csv ./example.csv -NoTypeInformation

	# First column of the first row; empty/DBNull retain provider scalar behavior.
	$count = Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'SELECT COUNT(*) FROM dbo.Example' -Scalar
	# No affected-row count or other success output.
	Invoke-Fast1GenericSqlQuery -SqlConn $connection `
		-Query 'UPDATE dbo.Example SET Name = @Name WHERE Id = @Id' -Parameters $parameters
}
finally {
	$connection.Dispose()
}
```

Parameter keys omit `@`. The factory requires an explicit SQL type, accepts
BigInt/enum zero, and preserves native values, including byte arrays. Omitted or
explicit null Value represents typed SQL NULL. Size accepts 0 through Int32.MaxValue;
Precision and Scale use byte ranges. Only positive metadata is forwarded; zero
retains provider defaults, including decimal scale inference. MAX size -1 and
output parameters are unsupported. The factory supports standard `-WhatIf` and
`-Confirm`; `-WhatIf` emits no descriptor. Stored procedures use `-CommandType StoredProcedure`.

`Invoke-Fast1GenericSqlQueryReader` emits a fresh ordered object for each row, retaining
native values and mapping SQL NULL to PowerShell null. Give every column a nonblank,
distinct SQL alias; names must be unique under ordinal case-insensitive comparison,
even for empty results. Only the first result with columns is selected. An empty
first tabular result emits nothing, even if a later result contains rows; commands
without a tabular result also emit nothing.

Rows arrive incrementally, but whole individual values can be materialized. A later
failure terminates delivery while previously emitted rows remain available. Pipeline
truncation, such as `Select-Object -First 1`, stops application reads and releases
owned resources. Reader disposal may wait for pending results, and later SQL statements
can still execute. Streaming does not promise cancellation, rollback, or atomic output.
PowerShell can suppress cleanup exceptions while stopping an upstream pipeline;
reader and command disposal are still attempted in order.

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

## Maintaining private loaders

`Fast1data.SqlServer/private/shared/Load.ps1` is the only shared behavior list.
Root and `private/archiving/ArchivingModel.psm1` dot-source it independently, giving
each module its own private functions. Root explicitly selects audit,
migration (including checksum and relative-path helpers), and the archiving
adapter; the model selects comparison/delay helpers and retains its local
functions and classes. Ordinary function files contain behavior; their loaders
supply dependencies.

Root bootstraps SqlClient and ScriptDom before loading shared behavior and the declaration-only
`private/archiving/Load.ps1`, then loads the archiving adapter and public commands.
Both libraries use `private/shared/Import-RequiredLibrary.ps1` with `-DllName` and
`-RequiredTypeName`. Other bundled managed DLLs use the same function without another
loader. It validates the selected RID asset on every call, even with a preload;
reuse requires matching name, version, culture, public key token and requested types.
Missing/corrupt assets and incompatible preloads fail with rebuild guidance.
Each executable migration file opens its own connection from the original `ConnStr`
under ambient transaction suppression and uses an owned command with timeout `0`.
The string determines authentication/options and configured/default catalog. History
uses its separate borrowed `SqlCmd` with unchanged settings and assigned transaction.
Input and whole-file validation precede execution allocation; zero-batch files need
no login. History follows a zero-transaction check and successful command, connection
and scope cleanup. Complete explicit SQL transactions within each file.
Session state remains isolated across files with pooling. Committed SQL can survive
execution or cleanup/history failure; follow the [migration retry guidance](Fast1Migration.md#failure-and-retry).
Direct model-first imports require explicit SqlClient bootstrap before parsing
model classes. After repairing a missing or corrupt required dependency, retry in
a fresh PowerShell process because class definitions persist within a process.
The three public commands, runtime requirements, configuration, and persisted
data contracts are unchanged. See the [loader validation guide](specs/005-explicit-module-loaders/quickstart.md)
for cold imports, fault isolation, and source/package checks.

## License

This project is licensed under the [MIT License](LICENSE).
