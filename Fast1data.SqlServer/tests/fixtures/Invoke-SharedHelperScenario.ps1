[CmdletBinding()]
param (
	[Parameter(Mandatory)][string]$DistributionRoot,
	[Parameter(Mandatory)][ValidateSet('L1', 'L2', 'L3', 'L4', 'L5')][string]$LoadingScenario,
	[Parameter(Mandatory)][ValidateSet('ARM', 'AMR', 'RAM', 'RMA', 'MAR', 'MRA')][string]$OperationOrder
)

$ErrorActionPreference = 'Stop'
try {
	$DistributionRoot = (Resolve-Path -LiteralPath $DistributionRoot).Path
	. (Join-Path $DistributionRoot 'private/shared/Get-RuntimeIdentifier.ps1')
	. (Join-Path $DistributionRoot 'private/shared/Import-SqlClientLib.ps1')
	Import-SqlClientLib
	$internalPaths = @('private/archiving/ArchivingModel.psm1', 'private/archiving/Metadata.psm1', 'private/shared/GenericSqlParam.psm1')
	if ($LoadingScenario -eq 'L2') {
		foreach ($path in $internalPaths) {
			Import-Module (Join-Path $DistributionRoot $path)
		}
	}
	$rootModule = Import-Module (Join-Path $DistributionRoot 'Fast1data.SqlServer.psd1') -PassThru
	$ownerBefore = & $rootModule { (Get-Command Write-LogMessage).Module }
	if ($LoadingScenario -in @('L3', 'L4', 'L5')) {
		& $rootModule {
			param ($Root, $Paths, $Scenario)
			$repetitions = 1
			if ($Scenario -in @('L4', 'L5')) {
				$repetitions = 2
			}
			for ($i = 0; $i -lt $repetitions; $i++) {
				foreach ($path in $Paths) {
					Import-Module (Join-Path $Root $path) -Force:($Scenario -eq 'L5')
				}
			}
		} $DistributionRoot $internalPaths $LoadingScenario
	}
	$config = New-PesterConfiguration
	$containers = @(New-PesterContainer -Path (Join-Path $PSScriptRoot 'SharedHelpers.Scenarios.ps1') -Data @{
		DistributionRoot = $DistributionRoot
		OperationOrder = $OperationOrder
		OwnerBefore = $ownerBefore
	})
	foreach ($suite in @('SqlCleanup', 'Archiving.Execution', 'Migration', 'Migration.Phase')) {
		$containers += New-PesterContainer -Path (Join-Path $DistributionRoot "tests/$suite.Tests.ps1")
	}
	$config.Run.Container = $containers
	$config.Run.PassThru = $true
	$config.TestRegistry.Enabled = $false
	$config.Output.Verbosity = 'None'
	$result = Invoke-Pester -Configuration $config
	$unexpectedSkips = @($result.Skipped | Where-Object { $_.Name -ne 'rejects differently cased sibling directories on a case-sensitive filesystem' })
	$observation = [ordered]@{
		Root = $DistributionRoot
		Loading = $LoadingScenario
		Order = $OperationOrder
		Total = $result.TotalCount
		Passed = $result.PassedCount
		Failed = $result.FailedCount
		Skipped = $result.SkippedCount
		UnexpectedSkipped = $unexpectedSkips.Count
		Errors = @($result.Failed | ForEach-Object { $_.ErrorRecord | ForEach-Object { $_.ToString() } })
	}
	'SHARED_HELPER_RESULT:' + ($observation | ConvertTo-Json -Depth 8 -Compress)
	if ($result.TotalCount -ne 136 -or $result.FailedCount -gt 0 -or $unexpectedSkips.Count -gt 0 -or $result.Result -ne 'Passed') {
		exit 1
	}
}
catch {
	Write-Error $_ -ErrorAction Continue
	exit 1
}
