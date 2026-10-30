# Existing Migration Command Contract

This documents the existing external interface and behavior strengthened by this feature. `Resolve-MigrationPhase` remains private; its shape is in [data-model.md](../data-model.md).

## Invocation and compatibility

```powershell
Invoke-Fast1Migration `
	-ConnStr $connectionString `
	-BasePath './migrations' `
	-Phase 'phase01' `
	-IgnoreScripts 'nested/skip.sql' `
	-ForceScripts 'nested/rerun.sql' `
	-WhatIf `
	-Verbose
```

| Parameter | Contract |
| --- | --- |
| `ConnStr` | Required SQL Server connection string; do not expose credentials in diagnostics. History access is required even for preview. |
| `BasePath` | Required existing root containing `migration.json` and phase directories. |
| `Phase` | Required literal phase property/directory name; wildcard selection is not supported. |
| `IgnoreScripts` | Optional names to skip; containment still applies, existence/checksum checks do not. |
| `ForceScripts` | Optional names allowed to execute despite history/drift; containment and existence still apply. Configured new scripts can also be forced. |
| `WhatIf`, `Confirm`, `Verbose` | Existing PowerShell common/ShouldProcess behavior. Verbose output presents ordered decisions and no-work state; WhatIf performs no mutations. |

Public parameters and exports, runtime/platforms, configuration shape, and history schema remain compatible. No structured public phase result is introduced.

## Configuration and identity

```json
{
	"phase01": {
		"scripts": ["002-first.sql", "nested/001-second.sql"]
	},
	"empty": {
		"scripts": []
	}
}
```

Run order is configured array order, not alphabetical or filesystem order. An existing empty phase succeeds with no work; a missing phase errors. Configuration, history, and selections share case-insensitive matching and backslash-to-forward-slash normalization. Actual files must be locatable under host filesystem case rules. Recorded names are normalized and phase-relative. History does not add unconfigured scripts.

## Validation and reporting

Before the first execution/history write, validate the entire phase. Reject missing inputs, configured duplicates, global ignore/force conflicts, paths outside the phase, missing non-ignored files, and unforced historical checksum drift. Containment includes ignored and forced entries and rejects sibling-prefix escapes and the directory itself. Unknown nonconflicting selections warn and add no work.

Errors identify the affected phase/script and rule; drift errors include expected/current SHA-256. Identical inputs produce the same decisions, warnings, and validation failures in preview and execution. Required history/file reads remain allowed under WhatIf. Preview reports eligible scripts in configured order and invokes neither execution nor history writing. Empty/all-skipped phases indicate no work.

## Execution, persistence, and failures

After successful validation and confirmation, execute each eligible script and record its success before starting the next. Insert new/forced-new scripts; update existing forced history with normalized name, current checksum, and database execution time. Locate historical rows by their preserved stored key so matching does not depend on database collation or separator spelling. Skips do not change history.

Execution failure terminates without recording that script or running later scripts. A history failure after successful execution also terminates before later work, but the script's effects may already exist. Earlier completed history remains intact. There is no automatic rollback or transaction over arbitrary scripts and history.

Scripts must be idempotent: retry after successful execution followed by failed recording can execute a script again. Configuration and SQL files are executable administrator inputs; permissions, schema setup, and recovery guidance remain in [Fast1Migration.md](../../../Fast1Migration.md). Validation is not a lock against subsequent file/history changes.

## Acceptance evidence

Verify phase rules through the private evaluator, public preview/coordination through command tests, and SQL persistence/error behavior against an explicitly selected test database. See [quickstart.md](../quickstart.md). No new endpoint, database adapter contract, schema migration, or public phase command is required.
