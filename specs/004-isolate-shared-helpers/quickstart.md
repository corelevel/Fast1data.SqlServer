# Quickstart: Validate Shared Helper Isolation

Run from the repository root in PowerShell. The import matrix and its fixtures live under `tests/` in each distribution. Controlled commands exclude integration filenames before discovery. See the [contract](contracts/shared-helper-boundaries.md) for exact assertions and [data model](data-model.md) for ownership and lifetime rules.

## Prerequisites

- PowerShell 7.6+ Core on a supported x64 host; existing SqlServer module and bundled SQL-client libraries.
- Pester 6+ for the repository packaging workflow, and PSScriptAnalyzer. This harness uses the nested-module targeting available in the existing Pester 6.2.0 installation; validation uses analyzer 1.25.0. No runtime dependency upgrade is part of this feature.
- .NET 10 SDK and dependency-feed access only if rebuilding runtime assets.
- For live suites, an explicitly selected disposable SQL Server instance, permission to create/drop test databases and create/alter fixture objects, and reviewed fixture configuration. Do not run integration suites against production.

Migration integration creates a unique database; archiving creates unique configuration/source/destination databases on the selected instance. Audit integration needs closed, immutable, nonempty audit files visible both to SQL Server and the selected discovery path, and permission to read them. Linux audit needs `smbclient` plus UNC/share access. Review each integration file's existing local connection/fixture settings before execution; these suites do not currently accept a common environment-variable configuration interface. Supply secrets locally and do not commit or print them.

No database change is required for consumers. Retain existing audit single-directory and archiving single-group execution constraints and existing recovery guidance.

## 1. Confirm tools and assets

```powershell
$PSVersionTable.PSVersion
Get-Module -ListAvailable Pester, PSScriptAnalyzer, SqlServer |
	Select-Object Name, Version
Get-ChildItem ./Fast1data.SqlServer/lib/*/Microsoft.Data.SqlClient.dll
```

Expected: supported tools and all declared `win-x64`, `linux-x64`, and `osx-x64` assets. Rebuild only when needed:

```powershell
pwsh -NoLogo -NoProfile -File ./build/build.ps1
```

This rebuilds existing runtime dependencies; it does not execute application migrations.

## 2. Preserve and run the audit regression

Use a fresh PowerShell process:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = './Fast1data.SqlServer/tests/Audit.Common.Tests.ps1'
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$config.Output.Verbosity = 'Detailed'
	$result = Invoke-Pester -Configuration $config
	if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0) {
		exit 1
	}
}
```

Planning baseline: 3 passes and 1 failure, with the regression expecting one verbose message and receiving zero. After implementation all four existing tests must pass. Do not relax the total count, remove the adverse import, or replace the logger with a mock.

## 3. Run source controlled coverage and import matrix

After the new matrix driver is implemented, this existing suite-selection pattern includes it automatically:

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

Exclude integration files by filename, not only tag: some suite-level setup allocates databases before tag filtering can provide the intended isolation.

Expected matrix evidence: 30 source loading/order tuples in separate workers, with all three operations sharing each worker; all six preference combinations, sequential verbose/quiet calls, real warnings, and unchanged caller preferences. Verify helper owners before/after imports, zero model helper exports, three root public commands, supported class imports, and model-local SQL/cleanup behavior. The matrix must report worker failures and nonzero exit codes to Pester and must not discover itself recursively.

The workers bootstrap SQL-client assemblies from the selected root for model-first cases, then import the model before root. The class fixture uses literal relative `using module` declarations; run it only after the assembly bootstrap in a fresh process. Neither worker may import the other distribution or assume source checkout paths. Reuse controlled SQL/discovery seams, keeping real loggers and class methods active.

Retain detailed `Archiving.Execution`, `SqlCleanup`, `Migration`, `Migration.Phase`, and applicable audit suites. SQL helper checks must assert actual text/type/parameter values, scalar output, non-query silence, and execution-error disposal. A run with no discovered cases, missing required matrix cases, or unexpected skips is not successful acceptance even if its failed count is zero.

## 4. Run required SQL checks

Once the explicitly selected test environment and local fixtures are configured, run the relevant integration files in fresh processes. For archiving, for example:

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

Repeat with `Migration.Integration.Tests.ps1` and the applicable `Audit.Integration.Windows.Tests.ps1` or `Audit.Integration.Linux.Tests.ps1`. During implementation parameterize or reuse fixture setup so required success/error/retry cases also execute after adverse imports; ordinary isolated-suite success alone is insufficient evidence of import compatibility. Use unique test databases and retain teardown attempts after failures.

Expected: unchanged durable progress, retry behavior, migration termination/preview, archiving processing order and foreign-key restoration. Exercise initialization, processing, cleanup-only, and primary-plus-cleanup failures and inspect original errors plus safe context. Record server/fixture prerequisites and any unavailable cases without recording secrets.

## 5. Build and validate the package

After local integration settings are reviewed and source checks pass:

```powershell
pwsh -NoLogo -NoProfile -File ./out/publish.ps1
```

This stages `out/Fast1data.SqlServer`, analyzes it, and runs **all tests including live integration**. It does not publish to a gallery. Do not describe it as SQL-free, and do not treat its staged output as a validated package if analyzer or tests fail.

Then run package controlled coverage in a separate process:

```powershell
pwsh -NoLogo -NoProfile -Command {
	$config = New-PesterConfiguration
	$config.Run.Path = @(Get-ChildItem ./out/Fast1data.SqlServer/tests/*.Tests.ps1 |
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

Expected: the other 30 loading/order tuples, class fixture and retained audit regression all pass against resolved paths beneath `out/Fast1data.SqlServer`. Compare normalized outcomes with source. Repeat required SQL scenarios from package test paths in fresh processes to avoid class/module state established during packaging. Verify all three runtime asset directories remain present.

If complete packaging cannot run, record controlled/staging observations separately from the outstanding package gate. Windows/Linux/macOS checks must be recorded independently; macOS does not acquire new audit-discovery support.

## 6. Analyze modified PowerShell files

Use repository analyzer settings if present at implementation time; none were found during planning. Include new untracked files as well as tracked changes. Load the module first for SQL-client type availability:

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

Resolve new errors/warnings and document unrelated pre-existing findings. Do not extend packaging's existing type-resolution filter or disable rules merely to pass. If analysis cannot run, report it as unavailable. Planning changes only Markdown, so this requirement applies to the subsequent implementation's modified scripts.

## Completion evidence

Record tested revision, tool versions, distribution roots, host/runtime, discovered matrix counts, passes/failures/skips, analyzer results, live SQL observations, and unavailable checks. All expected operational records and ownership checks must match the [contract](contracts/shared-helper-boundaries.md). Preserve the existing recovery/configuration documentation; update affected test guidance when adding the harness. Do not claim release readiness while material database integrity or package checks remain unverified.

## Execution environment for this implementation

Linux x64 and all three bundled runtime directories are available locally. Windows/macOS execution requires separate hosts; runtime files alone do not establish host validation. Audit discovery remains restricted to Windows/Linux. The user selected the existing test-local SQL configuration for live checks. Packaging executes those live suites too; no new configuration interface is introduced.

## Run a single matrix tuple

```powershell
pwsh -NoProfile -File ./Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1 `
	-DistributionRoot ./Fast1data.SqlServer -LoadingScenario L5 -OperationOrder MRA
```

Loading scenarios are L1 (root), L2 (model/metadata/parameter modules before root), L3 (internal imports into root), L4 (two repeated internal imports), and L5 (two forced internal imports). Operation orders are ARM, AMR, RAM, RMA, MAR and MRA. Substitute both the worker path and distribution root for package runs. The worker returns one `SHARED_HELPER_RESULT:` JSON record and a nonzero exit on failure, missing assertions or unexpected skips.

Each tuple requires exactly 136 Pester cases: eight logging/class/ownership/public-contract cases plus explicit SqlCleanup (25), Archiving.Execution (28), Migration (41), and Migration.Phase (34) containers. There are 30 unique tuples per distribution. The matrix emits a `SHARED_HELPER_MATRIX:` JSON record for parity comparison. Its only allowed inner skip is the existing case-sensitive-filesystem test when the host/filesystem cannot support it. Linux runs here have zero inner skips. Outer Windows-only audit tests intentionally skip on Linux.

`SharedHelpers.Classes.ps1` runs inside the worker's real-logger Pester fixture after assembly bootstrap. It checks literal class imports, construction, parameterless and preference-overload execution, and single-use rejection. Run the worker to exercise it; it is not a standalone SQL program.

Pester mocks for existing class consumers target `Fast1data.SqlServer/ArchivingModel`, the root's retained nested module instance. Forced imports can register a newer same-path model instance; owner checks and direct SQL tests inspect that instance separately. This avoids confusing a test-seam scope mismatch with changed production behavior.

The feature's `evidence/` JSON records contain analyzer findings and source/package test counts plus normalized matrix observations. They contain no connection settings. See `validation.md` for live SQL effects and remaining host obligations.
