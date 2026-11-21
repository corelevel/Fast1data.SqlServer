[CmdletBinding()]
param (
	[Parameter(Mandatory)][string]$RepositoryRoot,
	[Parameter(Mandatory)][string]$FixtureRoot,
	[Parameter(Mandatory)]
	[ValidateSet('CleanBuild', 'ReusedBuild', 'CleanStage', 'StandaloneStage', 'UnexpectedSource', 'PublishFailure', 'MissingPublished', 'CopyFailure', 'MissingCopied', 'MissingSource', 'StageCopyFailure', 'MissingStaged', 'UnexpectedStage', 'UnsafeBuild', 'UnsafeObsolete', 'UnsafeStage')]
	[string]$Scenario
)

$ErrorActionPreference = 'Stop'
$observation = [ordered]@{ Scenario = $Scenario; Complete = $false; Error = $null; HarnessError = $null; PublishCalls = @(); PesterCalls = 0; GalleryCalls = 0 }
try {
	# The parent is owned by this test run. No scenario may mutate the real checkout.
	if (-not [System.IO.Path]::IsPathFullyQualified($FixtureRoot)) {
		throw 'FixtureRoot must be absolute.'
	}
	$FixtureRoot = [System.IO.Path]::GetFullPath($FixtureRoot)
	$parent = [System.IO.Directory]::GetParent($FixtureRoot).FullName
	if (-not (Test-Path -LiteralPath (Join-Path $parent '.packaging-test-parent') -PathType Leaf) -or
		[System.IO.Path]::GetFileName($FixtureRoot) -notmatch '^[a-f0-9]{32}$' -or
		(Test-Path -LiteralPath $FixtureRoot)) {
		throw 'FixtureRoot must be a new GUID directory under a marked disposable parent.'
	}
	$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
	foreach ($relative in @('build/build.ps1', 'out/publish.ps1', 'build/SqlClientLoader.csproj')) {
		if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $relative) -PathType Leaf)) {
			throw 'Source-only packaging scenario unavailable: repository build/staging inputs are absent.'
		}
	}
	$null = New-Item -Path $FixtureRoot -ItemType Directory
	Set-Content -LiteralPath (Join-Path $FixtureRoot '.packaging-test-copy') -Value $FixtureRoot
	foreach ($directory in @('build', 'out', 'Fast1data.SqlServer')) {
		$null = New-Item -Path (Join-Path $FixtureRoot $directory) -ItemType Directory
	}
	foreach ($relative in @('build/build.ps1', 'build/SqlClientLoader.csproj', 'out/publish.ps1', 'README.md', 'Fast1Audit.md', 'Fast1Migration.md', 'LICENSE')) {
		Copy-Item -LiteralPath (Join-Path $RepositoryRoot $relative) -Destination (Join-Path $FixtureRoot $relative)
	}
	$sourceRoot = Join-Path $FixtureRoot 'Fast1data.SqlServer'
	foreach ($name in @('Fast1data.SqlServer.psd1', 'Fast1data.SqlServer.psm1', 'public', 'private', 'schema', 'tests')) {
		Copy-Item -LiteralPath (Join-Path $RepositoryRoot "Fast1data.SqlServer/$name") -Destination $sourceRoot -Recurse
	}
	$hostRid = 'linux-x64'
	if ($IsWindows) {
		$hostRid = 'win-x64'
	}
	$packagingState = @{
		AssetRoot = Join-Path $RepositoryRoot "Fast1data.SqlServer/lib/$hostRid"
		Required = @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll', 'Microsoft.SqlServer.Server.dll')
		PublishCalls = [System.Collections.Generic.List[object]]::new()
	}
	[AppDomain]::CurrentDomain.SetData('Fast1PackagingState', $packagingState)
	foreach ($dll in $packagingState.Required) {
		if (-not (Test-Path -LiteralPath (Join-Path $packagingState.AssetRoot $dll) -PathType Leaf)) {
			throw "Packaging fixture requires valid managed assets: $dll"
		}
	}
	function Initialize-FixtureBundle {
		param ([string]$Path)
		$state = [AppDomain]::CurrentDomain.GetData('Fast1PackagingState')
		$null = New-Item -Path $Path -ItemType Directory -Force
		foreach ($asset in Get-ChildItem -LiteralPath $state.AssetRoot | Where-Object Name -NE 'publish') {
			Microsoft.PowerShell.Management\Copy-Item -LiteralPath $asset.FullName -Destination $Path -Recurse
		}
		Set-Content -LiteralPath (Join-Path $Path 'fixture-native.bin') -Value 'native fixture bytes'
		$null = New-Item -Path (Join-Path $Path 'fixture-culture') -ItemType Directory
		Set-Content -LiteralPath (Join-Path $Path 'fixture-culture/resource.bin') -Value 'resource fixture bytes'
	}
	function dotnet {
		$state = [AppDomain]::CurrentDomain.GetData('Fast1PackagingState')
		$ridIndex = [array]::IndexOf($args, '-r')
		if ($ridIndex -lt 0 -or $args[0] -ne 'publish') {
			throw 'Unexpected controlled dotnet invocation.'
		}
		$rid = [string]$args[$ridIndex + 1]
		$project = [string]$args[1]
		$framework = ([xml](Get-Content -LiteralPath $project -Raw)).Project.PropertyGroup.TargetFramework
		$outputPath = Join-Path (Split-Path -Parent $project) "bin/Release/$framework/$rid/publish"
		$state.PublishCalls.Add(@{ Rid = $rid; Output = $outputPath })
		$global:LASTEXITCODE = 0
		if ($Scenario -eq 'PublishFailure') {
			$global:LASTEXITCODE = 17
			return
		}
		Initialize-FixtureBundle -Path $outputPath
		if ($Scenario -eq 'MissingPublished') {
			Remove-Item -LiteralPath (Join-Path $outputPath 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')
		}
	}
	$stageRoot = Join-Path $FixtureRoot 'out/Fast1data.SqlServer'
	$outside = Join-Path $FixtureRoot 'outside'
	$null = New-Item -Path $outside -ItemType Directory
	Set-Content -LiteralPath (Join-Path $outside 'sentinel.txt') -Value 'keep outside cleanup destination'
	$buildScenario = $Scenario -in @('CleanBuild', 'ReusedBuild', 'UnexpectedSource', 'PublishFailure', 'MissingPublished', 'CopyFailure', 'MissingCopied', 'UnsafeBuild', 'UnsafeObsolete')
	if (-not $buildScenario -or $Scenario -eq 'ReusedBuild') {
		foreach ($rid in @('win-x64', 'linux-x64')) {
			Initialize-FixtureBundle -Path (Join-Path $sourceRoot "lib/$rid")
		}
	}
	if ($Scenario -in @('ReusedBuild', 'StandaloneStage')) {
		Initialize-FixtureBundle -Path (Join-Path $sourceRoot 'lib/osx-x64')
		Set-Content -LiteralPath (Join-Path $sourceRoot 'lib/win-x64/old-source.txt') -Value 'old source'
	}
	if (-not $buildScenario) {
		$null = New-Item -Path (Join-Path $stageRoot 'lib/osx-x64') -ItemType Directory -Force
		Set-Content -LiteralPath (Join-Path $stageRoot 'previous-stage.txt') -Value 'previous stage'
		$null = New-Item -Path (Join-Path $sourceRoot 'lib/win-x64/publish') -ItemType Directory
		Set-Content -LiteralPath (Join-Path $sourceRoot 'lib/win-x64/publish/nested.txt') -Value 'nested output'
	}
	if ($Scenario -eq 'UnexpectedSource') {
		$null = New-Item -Path (Join-Path $sourceRoot 'lib/unexpected-rid') -ItemType Directory -Force
		Set-Content -LiteralPath (Join-Path $sourceRoot 'lib/unexpected-rid/sentinel.txt') -Value 'retain unexpected source'
	}
	if ($Scenario -eq 'MissingSource') {
		Remove-Item -LiteralPath (Join-Path $sourceRoot 'lib/linux-x64/Microsoft.SqlServer.TransactSql.ScriptDom.dll')
	}
	if ($Scenario -in @('UnsafeBuild', 'UnsafeObsolete', 'UnsafeStage')) {
		$scriptPath = Join-Path $FixtureRoot 'build/build.ps1'
		$needle = '$dest = Join-Path $PSScriptRoot "../Fast1data.SqlServer/lib/$rid"'
		$replacement = '$dest = Join-Path $PSScriptRoot "../outside"'
		if ($Scenario -eq 'UnsafeObsolete') {
			$needle = "(Join-Path `$libraryRoot 'osx-x64')"
			$replacement = "(Join-Path `$PSScriptRoot '../outside')"
		}
		if ($Scenario -eq 'UnsafeStage') {
			$scriptPath = Join-Path $FixtureRoot 'out/publish.ps1'
			$needle = "(Join-Path `$releaseRoot 'Fast1data.SqlServer')"
			$replacement = "(Join-Path `$releaseRoot '../outside')"
		}
		$code = Get-Content -LiteralPath $scriptPath -Raw
		if ([regex]::Matches($code, [regex]::Escape($needle)).Count -ne 1) {
			throw "Unsafe destination injection expected exactly one occurrence: $needle"
		}
		Set-Content -LiteralPath $scriptPath -Value $code.Replace($needle, $replacement)
	}
	# Intercept only the copy fault boundary; all preflight/cleanup/validation runs unchanged.
	function Invoke-FixtureCopy {
		[CmdletBinding()]
		param ([string]$LiteralPath, [string]$Destination, [switch]$Recurse)
		$isPublishedCopy = $LiteralPath -match '[/\\]publish$'
		$isStageBundleCopy = $Destination -match '[/\\]out[/\\]Fast1data.SqlServer[/\\]lib[/\\](win|linux)-x64$'
		if (($Scenario -eq 'CopyFailure' -and $isPublishedCopy) -or ($Scenario -eq 'StageCopyFailure' -and $isStageBundleCopy)) {
			throw 'Controlled copy failure'
		}
		Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
		if (($Scenario -eq 'MissingCopied' -and $isPublishedCopy) -or ($Scenario -eq 'MissingStaged' -and $isStageBundleCopy)) {
			Remove-Item -LiteralPath (Join-Path $Destination 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')
		}
		if ($Scenario -eq 'UnexpectedStage' -and $isStageBundleCopy -and -not (Test-Path -LiteralPath (Join-Path $stageRoot 'lib/unexpected-rid'))) {
			$null = New-Item -Path (Join-Path $stageRoot 'lib/unexpected-rid') -ItemType Directory
		}
	}
	Set-Alias -Name Copy-Item -Value Invoke-FixtureCopy -Scope Local
	# Isolate expensive analyzer execution in these controlled packaging cases. T019/T025
	# execute real stage-wide analysis. StageOnly must return before either call below.
	function Invoke-ScriptAnalyzer {
		param ([string]$Path, [switch]$Recurse, [string[]]$Severity)
		if (-not $Path -or -not $Recurse -or $Severity.Count -ne 2) {
			throw 'Unexpected analyzer invocation.'
		}
	}
	function Invoke-Pester {
		$observation.PesterCalls++
		throw 'StageOnly must not run Pester.'
	}
	function Invoke-FixturePublish {
		$observation.GalleryCalls++
		throw 'Packaging tests must not publish.'
	}
	Set-Alias -Name Publish-Module -Value Invoke-FixturePublish -Scope Local
	try {
		if ($buildScenario) {
			& (Join-Path $FixtureRoot 'build/build.ps1')
		}
		else {
			& (Join-Path $FixtureRoot 'out/publish.ps1') -StageOnly
		}
	}
	catch {
		$observation.Error = $_.Exception.Message
	}
	$observation.PublishCalls = @($packagingState.PublishCalls.ToArray())
	foreach ($pair in @(@{ Name = 'Source'; Path = $sourceRoot }, @{ Name = 'Stage'; Path = $stageRoot })) {
		$lib = Join-Path $pair.Path 'lib'
		$files = @()
		$rids = @()
		if (Test-Path -LiteralPath $lib) {
			$rids = @(Get-ChildItem -LiteralPath $lib -Directory | Sort-Object Name | Select-Object -ExpandProperty Name)
			$files = @(Get-ChildItem -LiteralPath $lib -File -Recurse | ForEach-Object {
				@{ Path = [System.IO.Path]::GetRelativePath($lib, $_.FullName).Replace('\', '/'); Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
			})
		}
		$observation[$pair.Name + 'Rids'] = $rids
		$observation[$pair.Name + 'Files'] = $files
	}
	$observation.OutsideSurvived = Test-Path -LiteralPath (Join-Path $outside 'sentinel.txt')
	$observation.PreviousStageSurvived = Test-Path -LiteralPath (Join-Path $stageRoot 'previous-stage.txt')
	$observation.UnexpectedSourceSurvived = Test-Path -LiteralPath (Join-Path $sourceRoot 'lib/unexpected-rid/sentinel.txt')
	$observation.Complete = $true
}
catch {
	$observation.HarnessError = $_.Exception.Message
}
'PACKAGING_RESULT:' + ($observation | ConvertTo-Json -Depth 8 -Compress)
if (-not $observation.Complete) {
	exit 1
}
