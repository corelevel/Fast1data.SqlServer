# Quickstart Validation: Consolidate Migration Phase Validation

This guide validates the private evaluator, public command, and SQL history behavior. See the [plan's verification mapping](plan.md#verification-mapping), [internal data model](data-model.md), [existing command contract](contracts/migration-command.md), and [recorded results](validation.md).

## Prerequisites and setup

- Run commands from the repository root in x64 PowerShell 7.4 or later.
- Use a compatible Pester installation; record the version. Planning found Pester 6.2.0. The tests use temporary files and Pester mocking/module-scope facilities.
- Command/integration tests require the existing SqlServer module and loadable Microsoft.Data.SqlClient. Follow [README source installation](../../README.md#install-from-source) if runtime assets need building; no build/dependency change is planned.
- Install/use PSScriptAnalyzer for the constitution's mandatory changed-PowerShell gate. Find and use repository settings when available. Planning found no settings file.
- Real SQL checks use the connection settings in `Migration.Integration.Tests.ps1`. Review them before running; the login must be able to create and drop disposable test databases.

Record environment versions without printing connection strings:

```powershell
$PSVersionTable
Get-Module -ListAvailable Pester, PSScriptAnalyzer, SqlServer |
	Select-Object Name, Version
```

## Phase behavior without SQL access

`Migration.Phase.Tests.ps1` loads only `Resolve-MigrationPhase` and retained filesystem helpers. It supplies real temporary configuration/files and in-memory history, with no SQL connection or deployment. Run it independently:

```powershell
Import-Module Pester -MinimumVersion 5.0 -Force
$migrationPhaseConfig = New-PesterConfiguration
$migrationPhaseConfig.Run.Path = './Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1'
$migrationPhaseConfig.Run.PassThru = $true
$migrationPhaseConfig.Output.Verbosity = 'Detailed'
if ($migrationPhaseConfig.PSObject.Properties['TestRegistry']) {
	$migrationPhaseConfig.TestRegistry.Enabled = $false
}
$migrationPhaseResult = Invoke-Pester -Configuration $migrationPhaseConfig

if ($migrationPhaseResult.Result -ne 'Passed' -or $migrationPhaseResult.PassedCount -eq 0) {
	throw 'Phase verification did not pass. Record failures and unavailable checks.'
}
```

Expected outcomes:

| Scenario | Observation |
| --- | --- |
| Literal phase and nonalphabetical nested scripts | Only the named phase is evaluated; configured order is retained, including bracketed names. |
| Existing empty versus missing phase | Empty returns an evaluation with empty `Scripts`; missing phase/config/directory yields an actionable error. |
| Case/slash variants in configuration, history, ignore, force | Matching and decisions agree across sources; actual file casing is preserved. |
| Configured duplicates and selection intersections | Rejected under shared rules, including an unknown name in both selections. |
| Unknown nonconflicting names | Warnings identify them; no extra script decisions are added. |
| Escape, absolute external path, sibling prefix, directory itself | Rejected, including ignored/forced variants and external files that actually exist. |
| Missing or drifted ignored file | Contained entry skips without file/hash checks. |
| Missing non-ignored file or unforced drift | Rejected; drift identifies expected/current checksums. |
| New, unchanged historical, forced historical, forced new | Correct eligibility/reason/checksum in configured order. |
| Valid first entry followed by invalid entry | No completed evaluation escapes; evaluator calls no execution/history writer. |

For platform-sensitive tests, use host-appropriate fixtures. Run the suite on Windows, Linux, and macOS or record each unavailable host as unrun. Include case-sensitive filesystem checks where that filesystem is available; do not infer them from Windows results.

## Command preview and coordination

Verify import/export boundaries, then run the isolated command suite:

```powershell
Import-Module './Fast1data.SqlServer/Fast1data.SqlServer.psd1' -Force
Get-Command -Module Fast1data.SqlServer

Import-Module Pester -MinimumVersion 5.0 -Force
$migrationCommandConfig = New-PesterConfiguration
$migrationCommandConfig.Run.Path = './Fast1data.SqlServer/tests/Migration.Tests.ps1'
$migrationCommandConfig.Run.PassThru = $true
$migrationCommandConfig.Output.Verbosity = 'Detailed'
if ($migrationCommandConfig.PSObject.Properties['TestRegistry']) {
	$migrationCommandConfig.TestRegistry.Enabled = $false
}
$migrationCommandResult = Invoke-Pester -Configuration $migrationCommandConfig

if ($migrationCommandResult.Result -ne 'Passed' -or $migrationCommandResult.PassedCount -eq 0) {
	throw 'Command verification did not pass. Record failures and unavailable checks.'
}
```

Expected exports remain `Invoke-Fast1Audit`, `Invoke-Fast1Migration`, and `Invoke-Fast1Archiving`; the evaluator is private and `Get-Migration` has no remaining caller. Controlled command tests mock the existing history/execution boundaries, not phase rules. They must prove:

- Paired execution/WhatIf inputs produce the same ordered eligible names, skips, warnings, and validation errors.
- WhatIf reads history but makes zero `Invoke-Migration` and zero `Set-Executed` calls, including forced cases.
- A valid first script followed by each late invalid case makes zero mutating calls in both modes.
- Empty/all-skipped phases report `Nothing to run` and make zero mutating calls.
- Each successful execution precedes its own history write, before the next execution. New/forced-new insert; forced historical updates use the preserved original key.
- Execution failure never records that script; recording failure stops after successful execution. Both stop later scripts and retain earlier progress.

The commands disable the unused TestRegistry facility when supported and retain TestDrive. This configuration was verified with Pester 6.2.0; planning's earlier default configuration hit a sandbox registry permission error. Report framework failure separately from failed behavior assertions and never count zero executed tests as a pass.

## Real SQL execution and history

`Migration.Integration.Tests.ps1` contains the live SQL cases and their connection settings. Its setup creates a uniquely named disposable database and installs the migration schema; teardown drops that database. The case-sensitive legacy-key test creates and drops an additional database with case-sensitive collation.

Grant the test login database creation/drop permissions and the permissions needed to install the schema, create fixtures, and execute migration SQL. See [Fast1Migration.md](../../Fast1Migration.md#database-setup).

Run the Integration fixtures against the connection declared in the test file:

```powershell
Import-Module Pester -MinimumVersion 5.0 -Force
$migrationSqlConfig = New-PesterConfiguration
$migrationSqlConfig.Run.Path = './Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1'
$migrationSqlConfig.Filter.Tag = 'Integration'
$migrationSqlConfig.Output.Verbosity = 'Detailed'
$migrationSqlConfig.Run.PassThru = $true
if ($migrationSqlConfig.PSObject.Properties['TestRegistry']) {
	$migrationSqlConfig.TestRegistry.Enabled = $false
}
$migrationSqlResult = Invoke-Pester -Configuration $migrationSqlConfig

if ($migrationSqlResult.Result -ne 'Passed' -or $migrationSqlResult.PassedCount -eq 0) {
	throw 'SQL verification did not pass. Record failures and unavailable cases.'
}
```

Fixtures use unique phase/table names and clean up only their own rows/tables in teardown. The seven SQL cases cover:

1. Multiple ordered scripts: actual SQL effects and one recorded success per eligible identity, unchanged checksums/timestamps on skips.
2. Changed forced rerun: normalized persisted name, updated checksum and execution time, no duplicate history. Forced new script inserts successfully.
3. Legacy backslash and case-variant stored names: evaluation matches; forced recording locates the existing row and normalizes its name. Repeat on an explicitly selected case-sensitive-collation database to prove behavior independent of case-insensitive SQL equality. Record the actual database collation. If no such database is available, mark that case unrun.
4. Actual SQL execution failure in a later script: no success record for that script, no later effect/history, earlier effects/history intact. Retain `Invoke-Sqlcmd -AbortOnError -ErrorAction Stop` behavior.
5. Successful SQL followed by actual history-write failure: use only fixture-owned state. One bounded failure fixture can seed a forced script's history and have that script remove its own history row before the writer's update, causing the existing missing-row error. Observe its successful SQL effect, the surfaced recording error, no later work, and earlier progress intact. Retry the idempotent script and verify safe effects and truthful recording. Do not claim rollback.
6. WhatIf against real readable history: no new effects, history count/name/checksum/timestamp changes, or forced updates. Compare eligibility to controlled execution fixtures with identical initial inputs.

Real SQL checks complement controlled orchestration tests; do not replace persistence/error assertions with mocks. An unavailable server/database or missing permissions means checks remain unverified, not passed. Do not log connection strings when reporting errors.

The two legacy-key cases run the same assertions against the main test database and a separately created case-sensitive database. Setup reports the main database collation; the case-sensitive fixture verifies its own comparison behavior.

## Static analysis and documentation review

Analyze every added/modified `.ps1`, `.psm1`, and `.psd1`, including tests. Expected initial scope is the evaluator, public command, history reader/writer, checksum helper, and all three migration test files. Expand that scope if implementation edits anything else. The removed reader is reviewed for absent callers rather than analyzed as an existing file.

```powershell
Import-Module PSScriptAnalyzer -ErrorAction Stop
$migrationAnalyzerFiles = @(
	'./Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1'
	'./Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1'
	'./Fast1data.SqlServer/private/migration/Get-Executed.ps1'
	'./Fast1data.SqlServer/private/migration/Set-Executed.ps1'
	'./Fast1data.SqlServer/private/shared/Get-FileChecksum.ps1'
	'./Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1'
)

$migrationAnalyzerOptions = @{
	Settings = @{
		Rules = @{
			PSReviewUnusedParameter = @{ CommandsToTraverse = @('BeforeAll') }
		}
	}
}
# If repository settings exist, use them and retain their rules. This setting
# expands parameter analysis into Pester setup; it disables/suppresses no rule.
$migrationAnalyzerFindings = foreach ($migrationAnalyzerFile in $migrationAnalyzerFiles) {
	Invoke-ScriptAnalyzer -Path $migrationAnalyzerFile @migrationAnalyzerOptions
}
$migrationAnalyzerFindings |
	Select-Object ScriptName, Line, Severity, RuleName, Message

git diff --check
```

Use repository settings if present; otherwise record defaults. Compare findings to a preserved pre-change baseline, resolve all introduced errors/warnings, and report unrelated existing findings with evidence. Analyzer unavailability/failure must be reported explicitly; parsing/Pester do not replace this gate. Do not suppress rules solely to pass analysis. Check tab indentation and multiline control flow from `AGENTS.md`.

Review migration help and `Fast1Migration.md` for contract consistency, preflight/preview behavior, host filesystem limits, setup/permissions, and successful-execution/failed-recording retry guidance. No schema/dependency/public parameter change should be needed.

## Report results

Record date, revision/worktree, OS/architecture/PowerShell/Pester/analyzer/SqlServer versions, exact commands/settings, test fixture scope, database identifier/collation without secrets, and passed/failed/skipped counts per layer. Map results to SC-001–SC-005 and distinguish unavailable cases from passing assertions. Record analyzer findings/baseline/remediation and documentation/import checks. Material unresolved data-integrity risks block release.

The current implementation results, incremental failures and fixes, SQL prerequisites,
analyzer scope/settings, and unavailable platform checks are recorded in [validation.md](validation.md).
