# Fast1 Migration

[Back to the module README](README.md)

Fast1 Migration is a lightweight SQL Server migration runner. It executes scripts in a configured order and records each successful execution with a SHA-256 checksum.

It is designed for migration scripts that are idempotent and safe to rerun. This is especially important when a script succeeds but recording its history entry fails: the next deployment can safely execute the script again.

## Features

- JSON-defined migration phases and script order
- SHA-256 checksum validation
- Migration history tracking
- Case-insensitive script matching
- Portable nested script paths
- Optional ignored and forced scripts
- Directory traversal protection
- Dry-run previews through `-WhatIf`
- Terminating SQL execution errors

## Requirements

- Permission to execute the migration scripts in the target database
- Permission to read and update `dbo.fast1_migration_history`

## Database setup

Connect to the target database and execute:

[`schema/migration/tables.sql`](Fast1data.SqlServer/schema/migration/tables.sql)

The script creates `dbo.fast1_migration_history` if it does not already exist. Include this table in the target database project or other schema-management process so it is not removed accidentally.

## Directory layout

A migration root contains `migration.json` and one directory per phase:

```text
migrations/
├── migration.json
├── phase01/
│   ├── 000-fix.sql
│   ├── 001-delete-old.sql
│   └── job007/
│       └── 000-kill-all-user-processes.sql
├── phase02/
│   └── 000-do-stuff.sql
└── phase03/
    └── 000-fix-This.sql
```

Scripts must remain inside their selected phase directory. Paths attempting to
escape it, such as `../outside.sql`, are rejected.

## Configuration

`migration.json` defines the exact execution order:

```json
{
	"phase01": {
		"scripts": [
			"000-fix-This.sql",
			"001-fix-That.sql",
			"job007/000-kill-all-user-processes.sql"
		]
	},
	"phase02": {
		"scripts": [
			"000-do-cool-stuff.sql"
		]
	}
}
```

Use `/` for nested paths in the configuration. The module also normalizes `\` to `/` in configuration and command parameters.

Phase names are looked up exactly rather than as wildcard patterns. Duplicate script names in a phase are rejected.

### Parameters

| Parameter | Required | Description |
| --- | --- | --- |
| `ConnStr` | Yes | SQL Server connection string for the target database. |
| `BasePath` | Yes | Directory containing `migration.json` and phase directories. |
| `Phase` | Yes | Migration phase to execute. |
| `IgnoreScripts` | No | Script names to skip. |
| `ForceScripts` | No | Script names to execute even when already recorded. |

Script comparisons for `IgnoreScripts` and `ForceScripts` are case-insensitive,
and both `/` and `\` separators are accepted.

## Execution behavior

For the selected phase, the module:

1. Loads execution history from `dbo.fast1_migration_history`.
2. Reads the ordered script list from `migration.json`.
3. Validates duplicates, ignored/forced conflicts, paths, and checksums.
4. Skips previously executed scripts whose checksums have not changed.
5. Stops if an executed script has been modified.
6. Executes new or forced scripts through `Invoke-Sqlcmd`.
7. Records new scripts or updates forced-script history.

If a script is listed in both `IgnoreScripts` and `ForceScripts`, execution
stops with an error.

### Ignore scripts

```powershell
Invoke-Fast1Migration `
	-ConnStr $connectionString `
	-BasePath '.\migrations' `
	-Phase 'phase01' `
	-IgnoreScripts '001-delete-old.sql'
```

### Force scripts

```powershell
Invoke-Fast1Migration `
	-ConnStr $connectionString `
	-BasePath '.\migrations' `
	-Phase 'phase01' `
	-ForceScripts 'job007/000-kill-all-user-processes.sql'
```

A forced script executes again and its stored checksum and execution timestamp
are updated. If it has never been recorded, it is inserted as a new history
entry.

## Dry run

Use PowerShell's `-WhatIf` support to preview the phase:

```powershell
Invoke-Fast1Migration `
	-ConnStr $connectionString `
	-BasePath '.\migrations' `
	-Phase 'phase01' `
	-WhatIf `
	-Verbose
```

The command reads migration history and validates files and checksums, but does
not execute scripts or update migration history.

## CI/CD

Store the connection string in the pipeline's secret-management facility:

```powershell
Invoke-Fast1Migration `
	-ConnStr $env:DB_CONNECTION `
	-BasePath '.\migrations' `
	-Phase 'phase01' `
	-Verbose
```

Do not commit database passwords or access tokens to source control.

## Usage

```powershell
$connectionString = @'
Data Source=<server>;
Initial Catalog=<database>;
Encrypt=True;
TrustServerCertificate=True;
Integrated Security=True;
Application Name=Fast1data.SqlServer;
'@

Invoke-Fast1Migration `
	-ConnStr $connectionString `
	-BasePath '.\migrations' `
	-Phase 'phase01' `
	-Verbose
```

An executable example is available in
[`example/migration/deploy-tempdb.ps1`](example/migration/deploy-tempdb.ps1).
