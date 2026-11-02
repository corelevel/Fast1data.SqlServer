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

Scripts must remain strictly inside their selected phase directory. Parent traversal,
absolute paths outside it, sibling directories sharing its prefix, and the phase
directory itself are rejected, even for ignored or forced entries. This is lexical
full-path containment; it does not add a symbolic-link resolution policy.

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

Use `/` for nested paths in the configuration. The module normalizes `\` to `/`
and matches configuration, history, ignore, and force names case-insensitively.
Configured casing is retained for file lookup: on a case-sensitive filesystem it
must locate the actual file. Contained rooted names become phase-relative names;
relative spelling is retained without general path-alias deduplication.

Phase names are looked up literally, including bracketed names, rather than as
wildcard patterns. Script order is the JSON array order. Duplicate script names
after case/separator matching are rejected. An existing empty script array is valid;
a missing phase, configuration file, or phase directory is an error.

### Parameters

| Parameter       | Required | Description                                                  |
| --------------- | -------- | ------------------------------------------------------------ |
| `ConnStr`       | Yes      | SQL Server connection string for the target database.        |
| `BasePath`      | Yes      | Directory containing `migration.json` and phase directories. |
| `Phase`         | Yes      | Migration phase to execute.                                  |
| `IgnoreScripts` | No       | Script names to skip.                                        |
| `ForceScripts`  | No       | Script names to execute even when already recorded.          |

Script comparisons for `IgnoreScripts` and `ForceScripts` are case-insensitive,
and both `/` and `\` separators are accepted.

## Execution behavior

For the selected phase, the module:

1. Loads execution history from `dbo.fast1_migration_history`.
2. Reads the ordered script list from `migration.json`.
3. Validates the entire phase: duplicates, ignored/forced conflicts, paths, files, and checksums.
4. Skips previously executed scripts whose checksums have not changed.
5. Stops if an executed script has been modified.
6. Executes new or forced scripts through `Invoke-Sqlcmd`.
7. Records new scripts or updates forced-script history.

All phase validation finishes before confirmation, execution, or history writes.
A valid first script followed by an invalid later entry executes no scripts.
Validation is a snapshot: it does not lock files or history against subsequent changes.

If a script is listed in both `IgnoreScripts` and `ForceScripts`, evaluation
stops with an error, including when that name is absent from configuration.
Other unknown ignore/force names produce distinct warnings and add no work.
Ignored entries still require containment but need not exist and are never hashed.
Force permits checksum drift and new scripts; containment and file existence still apply.
Empty or all-skipped phases succeed with `Nothing to run` in verbose output.

Configuration and SQL scripts are executable administrator inputs. Review them and
grant only the database permissions needed for the selected migrations and history.

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

History stores normalized phase-relative names. A forced historical update locates
the exact original stored key, including legacy backslashes or casing, and writes
the configured normalized name, checksum, and database UTC execution time. Skips
leave history and timestamps unchanged.

## Failure and recovery

Each eligible script finishes execution before its history is recorded, then the
next script starts. Execution failure terminates without recording that script.
Recording failure also terminates before later scripts, but successful SQL effects
may already exist without a corresponding history record. Earlier completed effects
and history remain durable; arbitrary scripts and history are not wrapped in a
phase transaction and no rollback is promised.

Require idempotent scripts. Inspect the failed SQL and history state, resolve the
failure, then retry. A script that executed successfully but was not recorded may
execute again on retry. Force deliberately reruns recorded work and does not make
non-idempotent scripts safe.

Isolated command tests are in `tests/Migration.Tests.ps1`; phase validation tests
are in `tests/Migration.Phase.Tests.ps1`. Neither suite connects to SQL Server.

Live SQL tests are in `tests/Migration.Integration.Tests.ps1`. Review the connection
settings in its integration `BeforeAll` block before running. The suite creates
uniquely named disposable databases, installs the migration schema, and drops the
databases during cleanup. The SQL login needs database creation/drop, schema and
fixture creation, and migration execution/history permissions. See the
[validation commands](specs/002-consolidate-migration-phases/quickstart.md).

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

The command reads migration history and validates the entire phase, including files
and checksums. Verbose output reports every run/skip decision and skip reason in
configured order; warnings and validation errors agree with execution for identical
inputs. Preview calls neither script execution nor history writing, including force.
Declining confirmation also leaves both mutation steps uncalled.

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

An executable example is available in [`example/migration/deploy-tempdb.ps1`](example/migration/deploy-tempdb.ps1).

Review its connection string before running it.
