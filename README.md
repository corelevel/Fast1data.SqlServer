# Fast1data.SqlServer

Fast1data.SqlServer is a PowerShell module for SQL Server administration and deployment workflows. It currently provides:

- [Fast1 Audit](Fast1Audit.md) — resumable import of SQL Server Audit (`.sqlaudit`) files into a SQL Server database.
- [Fast1 Migration](Fast1Migration.md) — ordered, checksum-protected execution of SQL Server migration scripts.

## Requirements

- PowerShell 7.4 or later
- SQL Server PowerShell module [SqlServer](https://learn.microsoft.com/en-us/powershell/sql-server/download-sql-server-ps-module) module
- An x64 Windows, Linux, or macOS runtime
- Network and database permissions required by the selected feature

The module bundles `Microsoft.Data.SqlClient` for these runtime identifiers:

- `win-x64`
- `linux-x64`
- `osx-x64`

## Install from source

Build the bundled SQL client libraries if `lib` is not already populated:

```powershell
.\build\build.ps1
```

Import the module directly from the repository:

```powershell
Import-Module .\Fast1data.SqlServer\Fast1data.SqlServer.psd1 -Force
```

Confirm that the public commands are available:

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

## Help

PowerShell command help is available after importing the module:

```powershell
Get-Help Invoke-Fast1Audit -Full
Get-Help Invoke-Fast1Migration -Full
```

## License

This project is licensed under the [MIT License](LICENSE).
