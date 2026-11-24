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
- `SELECT` and `INSERT` permissions on `dbo.fast1_migration_history`; `UPDATE` permission is also required for forced reruns of previously recorded scripts

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
			"000-fix.sql",
			"001-delete-old.sql",
			"job007/000-kill-all-user-processes.sql"
		]
	},
	"phase02": {
		"scripts": [
			"000-do-stuff.sql"
		]
	},
	"phase03": {
		"scripts": [
			"000-fix-This.sql"
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
6. Validates each selected file completely with the bundled TSql160Parser, then executes its original batches on one command and a separate owned connection per file, isolating session state (including `USE`) from history and later files.
7. Records completion once for the entire file after successful execution, transaction completion checks, and resource cleanup, including an empty file that requires no execution connection.

All phase validation finishes before confirmation, execution, or history writes.
A valid first script followed by an invalid later entry executes no scripts.
Validation is a snapshot: it does not lock files or history against subsequent changes.

The private history reader delegates to `Invoke-Fast1GenericSqlQueryReader` with a typed
NVarChar(32) phase filter. It streams `script_name` and `checksum` without changing
stored spelling, case, separators, or checksums; phase evaluation owns identity
normalization. Empty history emits no rows. The inner query releases its reader
then command before the history helper releases its owned connection, including
failure and early pipeline termination. A later read failure can leave rows already
delivered; cleanup preserves the primary error and safe cleanup details. Migration
order, checksum checks, force/ignore, preview and idempotent retry rules are unchanged.

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

Isolated command tests are in [`Fast1data.SqlServer/tests/Migration.Tests.ps1`](Fast1data.SqlServer/tests/Migration.Tests.ps1);
phase validation tests are in [`Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1`](Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1).
Neither suite connects to SQL Server.

### Live integration tests

Live SQL tests are in `Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1`.
Set `$env:FAST1_TEST_MIGRATION_SQL_CONN_STR` in the PowerShell session to select
the SQL Server test instance. Missing or blank configuration skips the suite.
Run from the repository root:

```powershell
$env:FAST1_TEST_MIGRATION_SQL_CONN_STR = 'Server=YOUR_TEST_SERVER;Initial Catalog=master;Integrated Security=True;Encrypt=True'
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1 -Output Detailed
```

Use the authentication and encryption options required by your test environment.
The suite creates uniquely named disposable databases, installs the migration
schema, and drops the
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

The command reads migration history and validates the phase configuration, paths,
files, and checksums. Verbose output reports every run/skip decision and skip reason
in configured order; phase-validation warnings and errors agree with execution for
identical inputs.

Preview does not parse SQL. SQL parsing happens inside the executor, after
confirmation, so a script with invalid SQL such as `SELECT FROM;` can pass preview
and fail during execution. Preview calls neither script execution nor history
writing, including force. Declining confirmation also leaves both mutation steps
uncalled.

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

## Script language and command ownership

No SqlServer PowerShell module installation is required. The distribution bundles
SqlClient and ScriptDom for the supported runtimes. The public invocation and history
schema are unchanged. Private `Invoke-Migration -ConnStr <string> -Script <string>`
owns its execution connection and command. `Set-Executed` takes a borrowed
`-SqlCmd <Microsoft.Data.SqlClient.SqlCommand>` for history.

Scripts must parse as TSql160 with quoted identifiers initially enabled. Standalone,
case-insensitive `GO` separates batches. The runner sends original source slices;
separator-like text in literals/comments, multiline statements, and batch-scoped
definitions retain their meaning. Leading/trailing/consecutive empty batches are
skipped. Empty, whitespace-only and comment-only files succeed and receive history.
Explicit `SET QUOTED_IDENTIFIER` must remain compatible with this parser dialect;
the parser resets its quoting mode at batch boundaries and does not discover server
session settings.

SQLCMD directives (`:r`, `:setvar`, `:connect`, and others), shell/utility commands,
and counted separators including `GO 1` and `GO 3` are unsupported. The spelling
`$(Name)` is reserved and rejected even in strings, identifiers and comments. A
directive mention inside a SQL literal/comment is otherwise ordinary text. Unsupported
constructs or syntax errors anywhere in a file prevent every batch in that file.

Every executable file uses one executor-owned connection; batches within it share
its owned command/session, so temporary objects and settings survive `GO`. History
stays on the original connection. Script `USE`, temporary objects, settings and
transaction state cannot reach history or later files. Pooling may reuse a physical
session after resetting its state; a unique SPID across files is not required.

The public owner forwards its original connection string unchanged for every file.
The executor rejects blank input and locally validates syntax, keywords and typed
option values with SqlConnectionStringBuilder, including for empty files. It then
reads and validates the complete script before allocating SQL resources. Invalid
and zero-batch files open no execution connection and perform no login probe.

For each executable file, the executor suppresses ambient transactions, creates and
opens a connection from that original string, then creates one command with timeout
`0`. Authentication, options and configured/default catalog come from the string.
Changing the history connection's database or redacting its password does not affect
this input. Connection-string authentication must be provisioned for the deployment;
external credential/token/callback objects are outside this interface. Initialization
failure terminates. Required libraries use the private `Import-RequiredLibrary`
bootstrap and the selected distribution's runtime bundle.

History keeps its own command's timeout and assigned transaction without switching
timeouts between scripts and history. `Set-Executed` preserves its borrowed connection,
timeout, transaction and lifetime while replacing operation text and typed parameters.
The executor owns command, connection and suppression scope and attempts disposal in
that order, keeping ambient suppression active through SQL cleanup. The public owner
allocates history resources only for confirmed eligible work, then disposes its
command and connection on every exit. Callers remain responsible for history transactions.

## Failure and retry

Files execute in configured order. After all batches, the runner requires zero
outstanding transactions through `SELECT @@TRANCOUNT`. Authors must finish every
explicit transaction within the file; the runner never commits one automatically.
History follows this check and successful command, connection and scope disposal,
before the next file. Input/read/preflight/parse/runtime/transaction/cleanup/history failures terminate the
operation. Diagnostics identify the file and original coordinates or executable batch
ordinal, retaining the underlying cause without copying SQL/provider details into
context messages. Cleanup attempts every owned resource and preserves the primary
failure when cleanup also fails.

There is no implicit phase rollback. Earlier batches can remain committed after a
later runtime failure. SQL success and history recording are separate completion
steps: history can fail after SQL has committed. Scripts must be independently
idempotent and manage any explicit SQL transactions themselves. A failed forced rerun
leaves the previous completion record unchanged; it does not undo earlier SQL effects.

For recovery, inspect the underlying failure and actual database state, repair the
script or history permissions, and rerun the same public invocation. Existing successful
files remain skipped. Use `-ForceScripts` explicitly when retrying a previously recorded
file whose contents changed. Review partial effects before forcing it; rerunning must
be safe without relying on a phase transaction.
