[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath(
	(Join-Path $PSScriptRoot '..')
)
$sourceModuleRoot = [System.IO.Path]::GetFullPath(
	(Join-Path $projectRoot 'Fast1data.SqlServer')
)
$releaseRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$moduleRoot = [System.IO.Path]::GetFullPath(
	(Join-Path $releaseRoot 'Fast1data.SqlServer')
)
$supportedRids = @(
	'win-x64'
	'linux-x64'
	'osx-x64'
)

# Validate sources before removing the previous staged package.
$requiredPaths = @(
	(Join-Path $sourceModuleRoot 'Fast1data.SqlServer.psd1')
	(Join-Path $sourceModuleRoot 'Fast1data.SqlServer.psm1')
	(Join-Path $sourceModuleRoot 'README.md')
	(Join-Path $sourceModuleRoot 'LICENSE')
	(Join-Path $sourceModuleRoot 'public')
	(Join-Path $sourceModuleRoot 'private')
	(Join-Path $sourceModuleRoot 'schema')
	(Join-Path $sourceModuleRoot 'tests')
)

foreach ($rid in $supportedRids) {
	$requiredPaths += Join-Path $sourceModuleRoot "lib\$rid\Microsoft.Data.SqlClient.dll"
}

$missingPaths = $requiredPaths | Where-Object {
	-not (Test-Path -LiteralPath $_)
}

if ($missingPaths) {
	throw "Cannot create the release package. Missing required path(s):`n$($missingPaths -join "`n")"
}

# Only the exact out\Fast1data.SqlServer directory may be removed.
$moduleParent = [System.IO.Directory]::GetParent($moduleRoot).FullName
if ($moduleParent -ne $releaseRoot -or
	[System.IO.Path]::GetFileName($moduleRoot) -cne 'Fast1data.SqlServer') {
	throw "Refusing to clean unexpected release path: $moduleRoot"
}

if (Test-Path -LiteralPath $moduleRoot) {
	Remove-Item -LiteralPath $moduleRoot -Recurse -Force
}

$null = New-Item -Path $moduleRoot -ItemType Directory

Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'Fast1data.SqlServer.psd1') -Destination $moduleRoot
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'Fast1data.SqlServer.psm1') -Destination $moduleRoot
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'README.md') -Destination $moduleRoot
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'LICENSE') -Destination $moduleRoot
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'public') -Destination $moduleRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'private') -Destination $moduleRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'schema') -Destination $moduleRoot -Recurse
Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'tests') -Destination $moduleRoot -Recurse

$moduleLibRoot = Join-Path $moduleRoot 'lib'
$null = New-Item -Path $moduleLibRoot -ItemType Directory

foreach ($rid in $supportedRids) {
	$source = Join-Path $sourceModuleRoot "lib\$rid"
	$destination = Join-Path $moduleLibRoot $rid
	Copy-Item -LiteralPath $source -Destination $destination -Recurse

	# Exclude accidentally nested build output from the published package.
	$nestedPublish = Join-Path $destination 'publish'
	if (Test-Path -LiteralPath $nestedPublish) {
		Remove-Item -LiteralPath $nestedPublish -Recurse -Force
	}
}

$manifestPath = Join-Path $moduleRoot 'Fast1data.SqlServer.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath

$missingStagedLibraries = $supportedRids | Where-Object {
	-not (Test-Path -LiteralPath (
		Join-Path $moduleLibRoot "$_\Microsoft.Data.SqlClient.dll"
	))
}

if ($missingStagedLibraries) {
	throw "Release validation failed for runtime(s): $($missingStagedLibraries -join ', ')"
}

if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
	throw 'PSScriptAnalyzer is required. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser'
}

Write-Host ''
Write-Host 'Running PSScriptAnalyzer...'
$analyzerResults = @(
	Invoke-ScriptAnalyzer -Path $moduleRoot -Recurse -Severity Error,Warning
)

if ($analyzerResults) {
	$analyzerResults |
		Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize |
		Out-Host
	throw "PSScriptAnalyzer reported $($analyzerResults.Count) warning(s) or error(s)."
}

$pesterModule = Get-Module Pester -ListAvailable |
	Where-Object Version -GE ([version]'6.0') |
	Sort-Object Version -Descending |
	Select-Object -First 1

if ($null -eq $pesterModule) {
	throw 'Pester 6 or later is required. Install it with: Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck'
}

Import-Module $pesterModule.Path -Force

Write-Host ''
Write-Host 'Running Pester...'
$pesterResult = Invoke-Pester `
	-Path (Join-Path $moduleRoot 'tests') `
	-Output Detailed `
	-PassThru

if ($pesterResult.FailedCount -gt 0) {
	throw "Pester reported $($pesterResult.FailedCount) failed test(s)."
}

Write-Host "Release package created successfully:"
Write-Host "  Path:    $moduleRoot"
Write-Host "  Module:  $($manifest.Name)"
Write-Host "  Version: $($manifest.Version)"
Write-Host ''
Write-Host 'Dry-run publishing command:'
Write-Host "  Publish-Module -Path '$moduleRoot' -Repository PSGallery -NuGetApiKey '<key>' -WhatIf -Verbose"
