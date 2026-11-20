# Validation Guide: Migration Execution Without SqlServer

**Feature**: [spec.md](spec.md) | **Contracts**: [contracts/migration-execution.md](contracts/migration-execution.md) | **Model**: [data-model.md](data-model.md)

This guide defines implementation acceptance; commands are not evidence they have already passed. Run from the repository root. The maintainer approved constitution 1.1.0 and module 0.1.0 on 2026-11-19; the amendment is applied. See [validation.md](validation.md) for executed checks and limitations.

## Prerequisites

- PowerShell 7.6+ Core and .NET 10 SDK for building dependencies.
- Pester 6+ and PSScriptAnalyzer; use the project analyzer settings if present. Neither tool is installed by this guide.
- A clean fresh process/environment where the SqlServer PowerShell module is absent from discoverable module paths. No SqlServer installation is needed for the new feature.
- Access to NuGet for dependency restore; supported native x64 Windows/Linux/macOS hosts for runtime acceptance.
- For live migration validation, explicitly select a disposable SQL Server test environment through the suite's existing `FAST1_TEST_MIGRATION_SQL_CONN_STR` opt-in. Supply it from the test environment's secret store. Do not use production credentials or paste secrets into logs/artifacts.
- The integration login needs create/drop-database permission and schema/fixture/migration/history permissions in uniquely named test databases. Retain the suite's database cleanup and case-sensitive database checks. Inspect all integration suites before running the release script: they have separate resource prerequisites.

## 1. Build every supported dependency bundle

```powershell
./build/build.ps1

$rids = @('win-x64', 'linux-x64', 'osx-x64')
$assemblies = @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')
foreach ($rid in $rids) {
	foreach ($assembly in $assemblies) {
		$asset = Join-Path ./Fast1data.SqlServer/lib "$rid/$assembly"
		if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
			throw "Missing bundled asset: $asset"
		}
	}
}
```

Expected: all publishes succeed and both assemblies exist for every RID with required transitive/native/resource output. Inspect restore results for the preserved user package versions; DLL presence alone is insufficient. Cross-publishing does not prove native import/execution.

## 2. Cold source import without the removed module

Run each command in a fresh process. The first intentionally fails if the test environment still exposes SqlServer.

```powershell
pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	if (Get-Module -ListAvailable -Name SqlServer) {
		throw 'Use a clean acceptance environment with SqlServer absent.'
	}
	Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
	Get-Command -Module Fast1data.SqlServer | Select-Object Name
	[Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser].Assembly.Location
	[Microsoft.Data.SqlClient.SqlConnection].Assembly.Location
}

pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psm1 -Force
	Get-Command -Module Fast1data.SqlServer | Select-Object Name
}
```

Expected: exactly `Invoke-Fast1Audit`, `Invoke-Fast1Migration`, `Invoke-Fast1Archiving`; no attempt to discover/install/import SqlServer during module initialization. Cold assemblies resolve from the selected distribution's current RID folder. Repeat on all supported native hosts.

Loader regression cases must cover repeated imports and preloaded compatible assemblies, plus missing/corrupt ScriptDom in marked disposable copies. Verify terminating dependency/RID context and no partial public command availability. Use the existing fresh-process fixtures; do not fault the working source tree.

### Generic DLL loader acceptance (FR-014)

The generic loader is implemented by T041-T043 and refinements T051/T053. Use fresh
source/staged results in [validation.md](validation.md), rather than earlier
specific-loader counts. See [contracts/required-library.md](contracts/required-library.md)
for exact validation/reuse rules and [data-model.md](data-model.md) for initialization states.

Run in a fresh process from the repository root. This loads the private definition directly so required types are checked on the initial call, before root import can preload dependencies:

```powershell
pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	$distribution = (Resolve-Path -LiteralPath ./Fast1data.SqlServer).Path
	. (Join-Path $distribution 'private/shared/Get-RuntimeIdentifier.ps1')
	. (Join-Path $distribution 'private/shared/Import-RequiredLibrary.ps1')
	$libraries = @(
		@{ DllName = 'Microsoft.Data.SqlClient.dll'; RequiredTypeName = 'Microsoft.Data.SqlClient.SqlConnection' }
		@{ DllName = 'Microsoft.SqlServer.TransactSql.ScriptDom.dll'; RequiredTypeName = 'Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser' }
		@{ DllName = 'Microsoft.SqlServer.Server.dll'; RequiredTypeName = 'Microsoft.SqlServer.Server.SqlFunctionAttribute' }
	)
	foreach ($library in $libraries) {
		$firstOutput = @(Import-RequiredLibrary @library)
		$assembly = [AppDomain]::CurrentDomain.GetAssemblies() |
			Where-Object { $_.GetName().Name -eq [System.IO.Path]::GetFileNameWithoutExtension($library.DllName) } |
			Select-Object -First 1
		$secondOutput = @(Import-RequiredLibrary @library)
		if ($firstOutput.Count -ne 0 -or $secondOutput.Count -ne 0 -or $null -eq $assembly) {
			throw 'Library initialization must succeed without success-stream output.'
		}
		if ($null -eq $assembly.GetType($library.RequiredTypeName, $false)) {
			throw 'Requested type is missing after initialization.'
		}
	}
	Import-Module (Join-Path $distribution 'Fast1data.SqlServer.psd1') -Force
	Get-Command -Module Fast1data.SqlServer | Select-Object Name
}
```

Expected: all three libraries initialize through the same function, the two calls per library return no objects, and root import exposes exactly the existing three commands. Repeat with `./out/Fast1data.SqlServer` as the selected distribution in another fresh process after staging. Record assembly locations and assert selected-bundle locations for cold loads; a compatible assembly already loaded by the host is a separate reuse case.

Run the affected loader and shared-helper suites after updating their fixtures:

```powershell
Invoke-Pester -Path @(
	'./Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1'
	'./Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1'
) -Output Detailed
```

Use marked disposable distribution copies for mutation cases. Do not fault the working source tree. Each cold fault uses a fresh process; warm faults first load successfully, then fault the selected copy's asset and repeat initialization. On Windows, use a renamed loaded file to represent a missing asset rather than overwriting a mapped DLL. A corrupt replacement can be created at the now-vacant original filename in the disposable copy.

| Case | Required result |
|---|---|
| Both primary DLLs and `Microsoft.SqlServer.Server.dll` | Same generic implementation, requested types available, no new production bootstrap or package needed |
| Repeat with intact bundle | Same assembly instance reused; no success output; required types checked again |
| Required-type checks on initial and repeated calls | All requested types validated; a deliberately nonexistent type terminates on either path |
| Omit optional required types | A valid third managed library still initializes through identity/load validation |
| Rooted/drive-qualified names, `../x.dll`, `..\x.dll`, either separator, wildcards, colon, empty or non-DLL name | Argument failure before loading; no path escape or fallback |
| Another managed DLL renamed to requested filename | Wrong identity rejected, including without a requested type |
| Same-name incompatible preload | Clear terminating failure; no alternate copy/context or version roll-forward |
| Compatible preload from elsewhere, intact selected bundle | Explicit reuse allowed; identity and required types validated |
| Cold missing/corrupt asset in source or stage | Requested DLL, RID, expected path, rebuild guidance, preserved cause; zero source/global fallback |
| Warm missing/corrupt selected asset | Failure despite prior compatible load; old rename-after-load success fixture replaced |
| Loader-definition or dependency fault during root import | Terminating stage context, restored preferences, no usable partial public operations |
| Module-loader trace/inventory/shared-helper scenarios | SqlClient then parser before dependent behavior; one generic definition; 23 private files if no other additions; unchanged exports and scope ownership |

Direct private calls and full root import cover different boundaries: the former proves the generic contract and the latter proves failed initialization cannot expose public behavior. Complete native Windows/Linux/macOS and staged variants before claiming distribution acceptance.

## 3. Run offline regressions

```powershell
$testPaths = Get-ChildItem ./Fast1data.SqlServer/tests/*.Tests.ps1 |
	Where-Object Name -NotLike '*.Integration.*' |
	Select-Object -ExpandProperty FullName
Invoke-Pester -Path $testPaths -Output Detailed
```

Expected: affected migration, phase, loader, shared-helper, cleanup, and other offline regressions pass. Keep phase validation and preview tests independent of SQL Server. Adapt old public success mocks for new resource ownership; do not fake typed provider/session behavior as proof of SQL correctness.

Required offline coverage includes whole-file preflight/parser outcomes, source coordinates, literals/comments containing `GO`, empty scripts/batches, line-leading directives versus quoted mentions, reserved substitutions inside quoted text, and counts after genuine separators. Missing/corrupt parser checks run cold so an already loaded assembly cannot hide the fault.

### Replacement private interface (FR-016)

After T057, run this inspection in a fresh process from the repository root. It checks the replacement parameter types without opening SQL resources:

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
$module = Get-Module Fast1data.SqlServer
& $module {
	$executor = Get-Command Invoke-Migration -CommandType Function
	$historyWriter = Get-Command Set-Executed -CommandType Function
	if (-not $executor.Parameters.ContainsKey('ConnStr') -or
		$executor.Parameters.ContainsKey('SqlCmd') -or
		$executor.Parameters['ConnStr'].ParameterType -ne [string]) {
		throw 'The executor must accept ConnStr without a SqlCmd parameter.'
	}
	if ($historyWriter.Parameters['SqlCmd'].ParameterType -ne [Microsoft.Data.SqlClient.SqlCommand]) {
		throw 'The history writer must retain its typed SqlCmd parameter.'
	}
}
```

Expected: no error after implementation. Current T010–T012 verify this interface; repeat the inspection after changes. This is a private-interface check; lifecycle and SQL effects require the offline and live suites above/below. Repeat against the staged manifest in a fresh process after staging.

T008–T012 must verify missing/empty/whitespace and locally malformed syntax, unknown keywords, and invalid typed option values with both empty and executable files. Input validation must precede a zero-batch success and allocate no execution connection/command. A valid zero-batch file opens no connection and does not authenticate. Test remaining provider construction/open failures separately; local validation alone cannot establish login or target availability. Assert that the original ConnStr is forwarded unchanged rather than rebuilt through SqlConnectionStringBuilder.

## 4. Select and run live SQL migration validation

Set `$env:FAST1_TEST_MIGRATION_SQL_CONN_STR` in the PowerShell session to select
the migration SQL test instance. The other integration suites use separate variables;
see the [integration test configuration table](../../README.md#live-integration-tests)
for all six settings and the audit prerequisites.

The migration suite requires explicit environment opt-in. Missing configuration skips
the suite with the required variable in its title; a skipped suite is not passing
integration evidence. The current tests target the ConnStr interface;
T013–T028 validate `Invoke-Migration -ConnStr -Script` and the updated
[per-file session contract](contracts/script-session.md). Verify original-string
forwarding, configured target/authentication, owned command/connection cleanup,
pooled isolation, ambient suppression, and final transaction checks. Previous
clone/restoration tests and counts do not establish FR-016 acceptance. Deployed
connection-string authentication modes require their provisioned test environments.

```powershell
if ([string]::IsNullOrWhiteSpace($env:FAST1_TEST_MIGRATION_SQL_CONN_STR)) {
	throw 'Select a disposable SQL test target through FAST1_TEST_MIGRATION_SQL_CONN_STR.'
}
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1 -Output Detailed
```

The suite creates unique databases, installs `schema/migration/tables.sql`, exercises configured fixtures, and drops its databases in cleanup. Verify fixture selection without printing the connection string. Required acceptance matrix:

| Scenario | Required observation |
|---|---|
| Multiple standalone `GO` batches and a batch-scoped definition | Every nonempty batch executes once in order; one history record |
| `GO` inside multiline strings/comments; leading/trailing/consecutive separators | Original meaning retained, no empty commands, no false boundaries |
| Temporary object used across batches | Same session observes earlier state |
| Explicit `SET QUOTED_IDENTIFIER` before later quoted SQL | Parsing follows the documented mode; accepted source executes without rewriting |
| Empty/whitespace/comment-only file | No batch execution; one successful history record |
| Syntax error in a later batch | Earlier effect absent; script/location diagnosed; no history or later scripts |
| Unsupported directive, substitution, `GO 1` or `GO 3` after valid SQL | Zero effects from the script; construct/location diagnosed |
| Runtime failure in a later batch | Earlier committed effects may exist; later work absent; no completion row |
| History command with nondefault timeout | History writer retains caller settings/transaction; executor independently creates its own command with timeout 0 |
| Transaction assigned to history command | Set-Executed retains transaction support; no caller command or assigned transaction is passed to executor |
| Two script files with temporary objects, settings, and database changes | Batches within a file share a session; history and next file are isolated from script session changes |
| Connection-string target and authentication | Executor opens from original ConnStr; configured target/options/authentication preserved; no history connection fallback |
| History connection changes database | Executor target still follows original ConnStr, not history's current database; no clone or ChangeDatabase snapshot requirement |
| Original string contains SQL authentication | Forward original ConnStr directly; do not reconstruct it from the opened history connection or log secrets |
| Provider authentication properties outside ConnStr | External SqlCredential/access-token/callback objects are not executor inputs; verify supported deployed connection-string authentication modes |
| Ambient TransactionScope | Script connection remains suppressed; original ambient context restored; history transaction behavior unchanged |
| Read/preflight/parse rejection or zero-batch script | Zero execution connection opens; zero-batch successful history still recorded |
| Malformed ConnStr with empty or executable file | Local syntax/keyword/typed-value rejection before execution allocation; no batch/history mutation; safe diagnostics |
| Execution connection creation/open failure | No history/next file; attempt owned command/connection/scope cleanup; preserve primary error |
| Owned command creation fails | No batch effects/history/next file; release already-created connection and suppression scope |
| Last batch leaves an explicit transaction open | Final `@@TRANCOUNT` check rejects completion; owned disposal may roll back uncommitted work; no history/next file and no automatic commit |
| Complete explicit BEGIN/COMMIT or BEGIN/ROLLBACK | Final transaction count zero and successful owned cleanup allow history recording |
| Final transaction check fails | No history/next file; failure identifies completion validation and preserves the underlying cause |
| Script and history timeout selection | Executor-owned command uses 0; public history command keeps its configured timeout without switching |
| Missing/closed history command connection | Set-Executed fails before mutation without allocating replacements; executor has no such caller prerequisite |
| Independent script/history commands | Original ConnStr forwarded for each script; only history command reused across records; no stale parameters |
| New and forced execution with legacy key spelling in case-sensitive history | Correct insert/update, checksum, normalized name, database UTC timestamp |
| Failed forced rerun | Previous completion record and timestamp unchanged |
| History write failure after SQL success | No next script; committed SQL remains; failure/retry documented |
| Script changes database using `USE` | Only script connection changes database; history connection stays at original target without public database restoration |
| Preview, declined confirmation, empty/all-skipped phase | Read-only reporting retained; zero script/history mutations and no mutation-command allocation |
| Owned resource exit on success/failure | Executor disposes owned command/connection/scope; public owner disposes history resources; all cleanup attempted |
| Execution plus multiple disposal failures | First execution error preserved; command, connection, and scope disposals all attempted; safe attached cleanup details |
| Disposal-only failure after successful SQL | Terminate without history/next script after attempting every owned disposal; no borrowed-command restoration stage |
| Idempotent retry after partial effects/history failure | Retry finishes safely and completion is correct |

For cases requiring special failure injection, use the test fixture's isolated wrappers/permissions and existing cleanup-error assertions. Do not require arbitrary provider objects to be mockable; real connection/session/transaction claims need real SQL evidence. Compare the active script's `@@SPID` to the concurrently open history session and verify within-file continuity. Consecutive files may reuse a pooled physical session; assert absence of earlier temporary objects and reset session settings/database/transaction state rather than distinct SPIDs for every file. Durable migration effects are expected to remain visible.

For FR-016, validate deployed connection-string authentication modes using the original string passed to the executor. Earlier clone/redaction/SqlCredential/token-property probes are historical and do not establish the new input contract. No external credential/token/callback parameter is added. Record unavailable SQL/native checks honestly and never print credentials or connection strings.

## 5. Analyze every modified PowerShell file

Import the built module so dependency types are available, then analyze all modified and newly added PowerShell files. If the project has an analyzer settings file, pass it through `-Settings` on every invocation below.

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
$changedPaths = @(
	git diff --name-only --diff-filter=ACMR
	git ls-files --others --exclude-standard
) | Sort-Object -Unique | Where-Object {
	[System.IO.Path]::GetExtension($_) -in @('.ps1', '.psm1', '.psd1')
}
foreach ($path in $changedPaths) {
	Invoke-ScriptAnalyzer -Path $path -Severity Error,Warning
}
```

Expected: no new errors/warnings; report unrelated existing findings and unavailable analyzer checks honestly. Do not add suppressions for new SqlClient/ScriptDom findings merely to bypass validation. Check `AGENTS.md` tab/multiline formatting separately where analyzer defaults differ.

## 6. Stage and validate the distribution

`out/publish.ps1` stages the module, analyzes it, and runs **all** tests, including SQL/audit/archiving integration suites. Configure their reviewed disposable resources before running it; the migration environment variable alone does not configure every suite.

```powershell
./out/publish.ps1
```

When the separate live resources are unavailable, stage and analyze without running
tests against the unrelated suites' embedded targets:

```powershell
./out/publish.ps1 -StageOnly
```

`-StageOnly` explicitly reports that tests were not run and release validation is
incomplete. Run affected offline tests against `out/Fast1data.SqlServer/tests` in a
fresh process, and still complete the full live/native checks before release.

After successful staging, repeat cold acceptance in a fresh clean process:

```powershell
pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	Import-Module ./out/Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
	Get-Command -Module Fast1data.SqlServer | Select-Object Name
	[Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser].Assembly.Location
	[Microsoft.Data.SqlClient.SqlConnection].Assembly.Location
}
```

Expected: assemblies resolve from the staged package rather than source or a globally installed dependency. Repeat relevant migration/loader suites against staged tests and the live workflow against the staged module; confirm source fallbacks cannot satisfy missing package assets. Verify both assemblies in every staged RID and execute native acceptance on Windows/Linux/macOS. Staging does not publish to a gallery; no external release is part of this guide.

## Evidence to record

Record host/runtime, package versions, source/staged paths, build and test counts, native-platform coverage, analyzer findings, and skipped/unavailable checks. Review manifest prerequisites/exports, public/private help, README installation, supported syntax, failure/retry guidance, and release notes against the contract. Record amendment approval/adoption and release-version decision. Unrun build/SQL/platform checks must remain explicit release limitations.

The original planning parser probe and the later offline synthetic cloning probes
are research evidence only. This spec review opened no SQL connection and ran no
migration/Pester acceptance. Implementation evidence, including build/staging/tests
actually run, is recorded in [validation.md](validation.md). Generic-loader results
and earlier clone-based FR-015 results retain their recorded scope and limitations;
they do not establish FR-016 acceptance. T033/T039–T042 require fresh evidence for the
replacement interface and applicable SQL/authentication/release/native obligations.

## Current task identifiers

The regenerated [tasks.md](tasks.md) uses T001–T042. Previous T056–T058 references
in design/history artifacts belong to the previous task sequence; see the
"Previous task ID mapping" in [tasks.md](tasks.md) for current obligations.
Use current T008–T012 for the executor interface, T013–T028 for batch/lifecycle/history
tests, T033 for source SQL, T037–T039 for analysis/offline/staging, T040 for full
release/staged SQL, T041 for native host acceptance and T042 for the evidence map.
StageOnly never establishes live SQL or full release acceptance. The integration
suite has no implicit migration target; provisioning the opt-in remains required.
