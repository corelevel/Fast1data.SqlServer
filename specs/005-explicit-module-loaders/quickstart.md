# Quickstart: Validate Explicit Module Loaders

Run commands from the repository root in PowerShell; use fresh child processes as shown. The explicit loaders and focused workers are implemented. See [loader contract](contracts/loader-boundaries.md), [ownership model](data-model.md), and [validation results](validation.md) for expectations and executed checks.

## Prerequisites

- PowerShell 7.6+ Core, supported x64 host, SqlServer module, and existing bundled runtime libraries.
- Pester 6+ and PSScriptAnalyzer. Planning used Pester 6.2.0, analyzer 1.25.0, and Windows/PowerShell 7.6.9.
- .NET 10 SDK/feed access only when rebuilding dependencies.
- Live SQL: explicitly selected disposable test instance and permission to create/drop test databases and create/alter fixture objects. Review each integration suite's existing local fixture configuration; there is no common environment-variable configuration interface. Keep credentials local.
- Audit integration: closed immutable nonempty audit files visible to SQL Server and discovery. Linux also needs smbclient and accessible UNC/share fixtures.
- Archiving: configuration/source/destination fixture databases on the selected instance, preserving the existing configuration/source-instance and primary-key requirements.

No schema/configuration upgrade is required. Existing single-directory audit and single-group archiving execution/recovery constraints remain.

## 1. Confirm tools and runtime assets

```powershell
$PSVersionTable.PSVersion
Get-Module -ListAvailable Pester, PSScriptAnalyzer, SqlServer |
	Select-Object Name, Version
Get-ChildItem ./Fast1data.SqlServer/lib/*/Microsoft.Data.SqlClient.dll
```

Expected: supported tools and all three declared runtime directories. If runtime assets need rebuilding:

```powershell
pwsh -NoLogo -NoProfile -File ./build/build.ps1
```

This rebuilds existing dependencies for win-x64, linux-x64, and osx-x64.

## 2. Run a genuinely cold root import

Use the root psm1 first to test bundled bootstrap without manifest-required SqlServer incidentally supplying the assembly:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psm1
	Get-Command -Module Fast1data.SqlServer | Select-Object Name
	[Microsoft.Data.SqlClient.SqlConnection].Assembly.Location
}
```

Expected: three public command names and the assembly beneath the selected source distribution. The focused loader tests must establish bootstrap-before-shared/feature loading, rather than infer order merely from successful import. Then validate the supported manifest entry separately:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1
	Get-Command -Module Fast1data.SqlServer | Select-Object Name
}
```

Expected: exactly Invoke-Fast1Audit, Invoke-Fast1Migration, and Invoke-Fast1Archiving. Manifest dependency processing can legitimately initialize SqlClient before root runtime.

## 3. Run focused loader coverage and retained audit regression

`ModuleLoaders.Tests.ps1` has 47 cases: four tagged US1, 42 tagged US2, and one tagged US3. Set `$config.Filter.Tag = 'US1'`, `'US2'`, or `'US3'` to select a story.

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = @(
		'./Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1'
		'./Fast1data.SqlServer/tests/Audit.Common.Tests.ps1'
	)
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$config.Output.Verbosity = 'Detailed'
	$result = Invoke-Pester -Configuration $config
	if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0) {
		exit 1
	}
}
```

Focused tests must cover the full dependency inventory, one shared list/eight local functions per consumer, exactly two initial shared executions, exclusive component ownership, class/typed-call availability, no ordinary-file loading directives, no private recursive discovery, and an unlisted nested private sentinel remaining inactive.

Fault-injection tests use disposable copies and fresh workers. They cover every selected private dependency, corrupt shared/type modules and SqlClient, and nonterminating errors inside required scripts. The worker is `tests/fixtures/Invoke-ModuleLoaderScenario.ps1`; mutations require a `.loader-test-copy` marker, which the harness creates only under Pester TestDrive. Run the fault cases through the harness:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = './Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1'
	$config.Filter.Tag = 'US2'
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$result = Invoke-Pester -Configuration $config
	if ($result.Result -ne 'Passed') {
		exit 1
	}
}
```

Expected: failed initialization identifies the dependency or owning model and unresolved metadata types; no affected operation remains usable, and caller preferences are unchanged. Declaration failures happen before loader runtime and can reject Import-Module without throwing to a caller using Continue. The worker captures those original parser/import errors separately. A preloaded compatible assembly retains the existing reuse behavior. Do not alter the working source tree to inject failures.

The audit regression must still emit exactly one verbose “No audit files found” message after adverse model import. Planning baseline: all four Audit.Common tests passed; retain their expectations.

## 4. Run controlled source suites and the import/order matrix

Exclude integration filenames before discovery because suite-level setup can allocate SQL objects:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = @(Get-ChildItem ./Fast1data.SqlServer/tests/*.Tests.ps1 |
		Where-Object Name -NotLike '*.Integration.*' |
		Select-Object -ExpandProperty FullName)
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$config.Output.Verbosity = 'Detailed'
	$result = Invoke-Pester -Configuration $config
	if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0) {
		exit 1
	}
}
```

Expected: affected controlled suites pass, including SqlCleanup, Archiving.Execution, Migration, Migration.Phase, applicable audit suites, new loader cases, and all 30 matrix tuples. Verify expected counts and allow only existing documented platform/filesystem skips. No missing cases or unexpected skips count as acceptance.

Existing loading scenarios: L1 root; L2 model/metadata/parameter modules before root after explicit bootstrap; L3 internal imports into root; L4 repeated internal imports; L5 forced repeated internal imports. Each runs ARM, AMR, RAM, RMA, MAR, and MRA operation orders. Existing workers preload SqlClient even for L1, so retain the separate cold test.

The existing inner total is 136 in both worker and driver. Update both if contained cases change, retaining completeness assertions. Ownership changes can amend existing cases without changing that count. Real loggers, all preference combinations, sequential verbose/quiet calls, SQL parameter/scalar/non-query contracts, error disposal, seven-type class fixtures, Execute overloads and single-use guards remain covered.

For a diagnostic tuple:

```powershell
pwsh -NoLogo -NoProfile -File ./Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1 `
	-DistributionRoot ./Fast1data.SqlServer -LoadingScenario L2 -OperationOrder MRA
```

Expected: one SHARED_HELPER_RESULT JSON record and exit zero. Use the existing nested module mocking seam; distinguish retained class ownership from a newer same-path model instance after forced imports.

## 5. Run required SQL checks

Once local test fixtures are reviewed/configured, run each relevant integration suite in an independent process. Example:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = './Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1'
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$config.Output.Verbosity = 'Detailed'
	$result = Invoke-Pester -Configuration $config
	if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0) {
		exit 1
	}
}
```

Repeat for Migration.Integration.Tests.ps1 and applicable Audit.Integration.Windows.Tests.ps1 or Audit.Integration.Linux.Tests.ps1. Include existing adverse-import success/error/retry coverage where available; retain relevant processing/cleanup and durable-state cases.

Expected: unchanged migration validation/order/checksum/preview and failure termination; audit completed/ignored offsets; archiving order, checkpoints, retries, working sets, constraint restoration, and primary/cleanup errors. Verify SQL-specific effects against SQL Server where mocks cannot establish correctness. Retain teardown attempts after failure.

## 6. Analyze modified scripts

Load the source module for type availability. Include newly added files and existing tracked changes; use repository settings if present at implementation time. None were found during planning.

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
$changed = @(
	git diff --name-only HEAD -- '*.ps1' '*.psm1' '*.psd1'
	git ls-files --others --exclude-standard -- '*.ps1' '*.psm1' '*.psd1'
) | Sort-Object -Unique
foreach ($file in $changed) {
	if (Test-Path -LiteralPath $file -PathType Leaf) {
		Invoke-ScriptAnalyzer -Path $file -Severity Error, Warning
	}
}
```

Resolve all new warnings/errors; report unrelated existing findings. Do not disable rules or extend packaging's existing SqlClient type filter. Report unavailable analysis explicitly. Check AGENTS.md multiline/tab formatting too.

## 7. Package and independently validate the staged distribution

After source and required local SQL checks:

```powershell
pwsh -NoLogo -NoProfile -File ./out/publish.ps1
```

This stages out/Fast1data.SqlServer, validates assets/manifest, runs analyzer, and executes all tests including live SQL integration. It does not publish to a gallery. A staged directory after failure is not a validated package.

Repeat steps 2–5 in fresh processes using out/Fast1data.SqlServer for every module, test, and worker path. Run the same controlled selection with that directory; do not reuse source session state. Assert private functions, classes/modules, and bundled assemblies come from the selected package. New Load scripts must be included by the existing recursive private-tree copy.

For the staged controlled suites (in a new process), select paths explicitly:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = @(Get-ChildItem ./out/Fast1data.SqlServer/tests/*.Tests.ps1 |
		Where-Object Name -NotLike '*.Integration.*' |
		Select-Object -ExpandProperty FullName)
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$result = Invoke-Pester -Configuration $config
	if ($result.Result -ne 'Passed') {
		exit 1
	}
}
```

Expected: 30 additional package matrix tuples, focused loader cases, retained regression coverage, fixed public metadata, all runtime assets, and normalized source/package parity. If complete packaging cannot run, report staging/controlled observations separately from the outstanding package gate.

## Completion evidence

Record revision/working-tree baseline, tools, host/runtime, distribution roots, expected/discovered cases, passes/failures/skips, loader negative cases, analyzer findings, package results, and live SQL observations without connection secrets. Record Windows/Linux/macOS separately; macOS gains no audit-discovery support.

Planning completed only the four-test audit baseline and disposable type/scope feasibility probes. Full matrix, live SQL, package acceptance, and other hosts remain implementation checks. Do not report unrun checks as passing.

