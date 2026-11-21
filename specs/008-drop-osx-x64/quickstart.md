# Validation Guide: Drop macOS x64 Support

**Feature**: [spec.md](spec.md) | **Contract**: [contracts/runtime-support.md](contracts/runtime-support.md) | **Model**: [data-model.md](data-model.md)

These scenarios validate the implementation after the tasks are generated and completed. `RuntimeSupport.Tests.ps1` and `Packaging.Tests.ps1` are planned files, not present at planning time. No build, runtime test, or SQL acceptance result is claimed by this guide.

## Prerequisites

- Use a disposable checkout of the implemented feature for stale-bundle scenarios. The real build intentionally deletes the obsolete source bundle and staging replaces its own output directory.
- Run from the checkout root using PowerShell 7.6+ Core on native x64 Windows or Linux with an x64 PowerShell process. Repeat supported-host acceptance on both systems.
- Install a .NET SDK supporting `net10.0`, Pester 6+, and PSScriptAnalyzer. NuGet restore needs network access or populated package caches. No separate SqlServer PowerShell module is required.
- Use fresh `pwsh -NoProfile` child processes for imports to avoid retained PowerShell classes/assembly state.
- For live acceptance, supply the test environment variables and permissions described in [README.md](../../README.md#live-integration-tests), [migration](../../Fast1Migration.md#live-integration-tests), [archiving](../../Fast1Archiving.md#tests), and [audit](../../Fast1Audit.md#live-integration-tests). Use explicitly selected test SQL Server resources. Do not print connection strings or credentials.

```powershell
$PSVersionTable.PSVersion
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
Get-Module -ListAvailable Pester, PSScriptAnalyzer | Select-Object Name, Version
$sourceRoot = (Resolve-Path ./Fast1data.SqlServer).Path
$stageRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) 'out/Fast1data.SqlServer'))
```

Expected: Core 7.6+, reported OS X64, process X64, Pester 6+ and analyzer available. Record actual versions/platforms.

## 1. Focused runtime and packaging acceptance

```powershell
Invoke-Pester -Path ./Fast1data.SqlServer/tests/RuntimeSupport.Tests.ps1,./Fast1data.SqlServer/tests/Packaging.Tests.ps1 -Output Detailed
```

The planned suites must establish:

| Area | Cases | Expected outcome |
|---|---|---|
| Runtime selection | Windows/Linux, OS X64, process X64 | Matching RID only. |
| macOS rejection | X64 and ARM64, stale bundle absent/present, cold/compatible preload, both `.psd1`/`.psm1` | Terminating platform rejection naming both alternatives; no bundle lookup or downstream/database attempts. |
| Other rejection | Unknown OS; Windows/Linux reported ARM64/X86; X64 OS with non-X64 process | No fallback, no database attempts. Include X64 process on reported ARM64 OS. |
| Supported dependency faults | Missing/corrupt assets and incompatible preloads | Existing selected DLL/RID/path/rebuild/fresh-process diagnostics, distinct from unsupported-platform errors. |
| Build | Clean/reused isolated roots | Publish called for two targets only; old macOS source bundle removed; both required DLLs retained. |
| Stage | Clean/reused source/stage, including macOS bundles | Exact two-RID package, no obsolete bundle or nested publish directory. |
| Failure/containment | Failed publish, missing required retained assets, unexpected source/stage target, unsafe cleanup destination | Terminating failure; preflight does not remove prior stage; cleanup cannot escape validated destination. |

Native-fact simulation changes only OS flags and RuntimeInformation architecture expressions in marked disposable copies, checking that every intended substitution occurred. Keep actual selector and import logic. Never force global host variables or mock the resolver to throw. Packaging tests operate in disposable roots, with controlled external publish calls as needed; they must not rebuild or delete the developer's real assets. They are source-repository tests and may explicitly skip source-only build scenarios when copied into a staged module without build scripts.

## 2. Real clean build and stage

In a fresh disposable checkout with no prior bundles:

```powershell
./build/build.ps1
./out/publish.ps1 -StageOnly
$expectedRids = @('linux-x64', 'win-x64')
foreach ($distribution in @($sourceRoot, $stageRoot)) {
	$actualRids = @(Get-ChildItem -LiteralPath (Join-Path $distribution 'lib') -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
	if (($actualRids -join ',') -cne ($expectedRids -join ',')) {
		throw "Unexpected runtime bundles in $distribution"
	}
	foreach ($rid in $expectedRids) {
		foreach ($dll in @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')) {
			$asset = Join-Path $distribution "lib/$rid/$dll"
			if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
				throw "Missing required library: $asset"
			}
		}
	}
}
```

Expected: both commands succeed; exactly two directories in both `lib` roots; both required DLLs and existing native/resource assets are retained. Compare source/stage file lists and SHA-256 hashes of retained bundles; no macOS bundle appears. `-StageOnly` checks staged import and analyzer, but does not run Pester or publish anything.

## 3. Reused build and stage

In the same disposable checkout, seed obsolete directory markers, then repeat the real build and stage:

```powershell
foreach ($distribution in @($sourceRoot, $stageRoot)) {
	$obsoleteRoot = Join-Path $distribution 'lib/osx-x64'
	$null = New-Item -Path $obsoleteRoot -ItemType Directory -Force
	Set-Content -LiteralPath (Join-Path $obsoleteRoot 'obsolete-marker.txt') -Value 'obsolete bundle fixture'
}
./build/build.ps1
./out/publish.ps1 -StageOnly
foreach ($distribution in @($sourceRoot, $stageRoot)) {
	if (Test-Path -LiteralPath (Join-Path $distribution 'lib/osx-x64')) {
		throw "Obsolete bundle remains in $distribution"
	}
}
```

Repeat the exact RID/DLL and source/stage hash checks from scenario 2. Separately verify staging without a rebuild: seed `lib/osx-x64/obsolete-marker.txt` again in source and stage, run only `out/publish.ps1 -StageOnly`, and verify the stage still contains exactly two bundles. Source may still contain the deliberately seeded obsolete fixture in this standalone-staging case; the allowlist must exclude it. Run the build again to return source to the exact retained set before the full shared-helper matrix.

The isolated packaging suite also covers obsolete directory names containing fixture DLLs. Runtime rejection tests must include a valid leftover asset/preload case; an empty directory alone does not prove that valid old libraries cannot re-enable support.

## 4. Source and staged import/command regressions

Run each worker command in a fresh process for both distributions:

```powershell
foreach ($distribution in @($sourceRoot, $stageRoot)) {
	$worker = Join-Path $distribution 'tests/fixtures/Invoke-ModuleLoaderScenario.ps1'
	foreach ($scenario in @('Manifest', 'Direct', 'ModelFirst')) {
		pwsh -NoProfile -File $worker -DistributionRoot $distribution -Scenario $scenario
		if ($LASTEXITCODE -ne 0) {
			throw "Loader scenario $scenario failed for $distribution"
		}
	}
	Invoke-Pester -Path (Join-Path $distribution 'tests/ModuleLoaders.Tests.ps1') -Output Detailed
	Invoke-Pester -Path (Join-Path $distribution 'tests/SharedHelpers.Import.Tests.ps1') -Output Detailed
}
```

Expected: worker `MODULE_LOADER_RESULT` records report `Complete: true`, correct distribution provenance and no errors. Both root entry points preserve the six commands and factory behavior. Shared-helper acceptance retains its five loading patterns by six operation orders, frozen command metadata and defining module ownership; only runtime-asset expectations change. Do not loosen fixed counts, snapshots, or skips to hide failures.

Run the remaining offline command suites from source and stage:

```powershell
foreach ($distribution in @($sourceRoot, $stageRoot)) {
	$testPaths = Get-ChildItem -LiteralPath (Join-Path $distribution 'tests') -Filter '*.Tests.ps1' |
		Where-Object Name -NotLike '*.Integration.*' |
		Where-Object Name -NotIn @('ModuleLoaders.Tests.ps1', 'SharedHelpers.Import.Tests.ps1', 'RuntimeSupport.Tests.ps1', 'Packaging.Tests.ps1') |
		Select-Object -ExpandProperty FullName
	Invoke-Pester -Path $testPaths -Output Detailed
}
```

Run staged `RuntimeSupport.Tests.ps1` separately where its distribution-copy fixture is supported. Record source/stage results and native Windows/Linux results distinctly. Native macOS rejection is additional host evidence when available; record it as unavailable when only simulation was possible. An actual macOS cold import should fail before any database setup, even with a leftover valid bundle. It must name both supported alternatives, without suggesting a macOS rebuild.

## 5. Real SQL acceptance on retained hosts

After locally configuring the documented environment variables, run existing acceptance against the explicitly selected test resources on both hosts. Test suites create and remove their own fixtures; use their documented permissions.

```powershell
$auditSuite = './Fast1data.SqlServer/tests/Audit.Integration.Linux.Tests.ps1'
if ($IsWindows) {
	$auditSuite = './Fast1data.SqlServer/tests/Audit.Integration.Windows.Tests.ps1'
}
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1,./Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1,./Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1,$auditSuite -Output Detailed
```

Repeat against staged test paths for final-distribution acceptance using the same explicitly selected test resources. Expected: configured command scenarios pass, migration checksums/order/history/preview and retries remain valid, audit/archiving progress remains compatible, and query output/ownership contracts remain unchanged. Missing environment variables, skipped suites, or unavailable hosts do not establish acceptance. No schema-format migration should be added for platform removal.

## 6. Analyzer, metadata, and upgrade review

Run `Invoke-ScriptAnalyzer` on every changed or newly added `.ps1`, `.psm1`, and `.psd1`, including build/staging scripts and fixtures. Discover repository settings and pass `-Settings` when present; none were found during planning. Use package-wide analyzer validation through real staging as well. Resolve newly introduced warnings/errors and report unrelated baseline findings; do not add analyzer suppressions to make validation pass.

```powershell
$manifest = Import-PowerShellDataFile ./Fast1data.SqlServer/Fast1data.SqlServer.psd1
$manifest.ModuleVersion
$manifest.PrivateData.PSData.Tags
$manifest.PrivateData.PSData.ReleaseNotes
rg -n 'osx-x64|macOS|ModuleVersion|PowerShellVersion' README.md Fast1data.SqlServer/Fast1data.SqlServer.psd1 build/build.ps1 out/publish.ps1 .specify/memory/constitution.md
```

Expected: module 0.2.0, Windows/Linux current platform claims only, PowerShell 7.6+ unchanged, explicit immediate macOS-removal and host-transition guidance, and constitution 2.0.0 with authorized amendment and preserved ratification/history. macOS mentions describing removal, cleanup/tests, and historical amendments are valid; current support promises are not. Review current command help and feature guides for conflicting claims. Leave historical specs and previously published releases intact.

Upgrade guidance must retain database state, history, configuration and portable migration identities; users must arrange equivalent file/share access and permissions on their new supported host. No database-format conversion is required.

## Evidence to record during implementation

| Check | Planning-time status |
|---|---|
| Design artifacts and requirement mapping | Generated and reviewed; relative links in all seven feature documents resolve, and all eight PowerShell documentation blocks parse without syntax errors |
| Focused runtime/package suites | Not run; implementation pending |
| Real clean and stale build/stage, asset hashes | Not run |
| Native Windows x64 source/staged acceptance | Not run |
| Native Linux x64 source/staged acceptance | Not run |
| Native macOS rejection | Not run; simulated coverage planned separately |
| Existing offline and live SQL acceptance | Not run |
| Changed-file and package-wide analyzer | Not run; no PowerShell files changed by planning |
| Module/policy version adoption and upgrade review | Planned, not applied |

Record versions, host OS/architecture, source/stage identity, pass/fail/skip counts, baseline issues and unavailable prerequisites without exposing secrets. StageOnly success alone is not release completion.
