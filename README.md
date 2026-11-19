# Fast1data.SqlServer

Fast1data.SqlServer is a PowerShell module for SQL Server administration and deployment workflows. It currently provides:

- [Fast1 Audit](Fast1Audit.md) — resumable import of [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine) (`.sqlaudit`) files into a SQL Server database.
- [Fast1 Migration](Fast1Migration.md) — ordered, checksum-protected execution of SQL Server migration scripts.
- [Fast1 Archiving](Fast1Archiving.md) — resumable, batch-based archiving and purging between SQL Server databases.

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

## Help

PowerShell command help is available after importing the module:

```powershell
Get-Help Invoke-Fast1Audit -Full
Get-Help Invoke-Fast1Migration -Full
Get-Help Invoke-Fast1Archiving -Full
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
`Migration.Integration.Tests.ps1`. Review each integration suite's connection and
fixture settings before selecting it. See the feature guides for prerequisites.

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
