BeforeDiscovery {
	$script:packagingRepository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
	$script:hasPackagingSource = Test-Path -LiteralPath (Join-Path $script:packagingRepository 'build/build.ps1')
}

BeforeAll {
	$script:repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
	Set-Content -LiteralPath (Join-Path $TestDrive '.packaging-test-parent') -Value 'disposable packaging scenarios'
	function Invoke-PackagingWorker {
		param ([string]$Scenario)
		$fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
		$output = @(& (Join-Path $PSHOME 'pwsh') -NoProfile -File (Join-Path $PSScriptRoot 'fixtures/Invoke-PackagingScenario.ps1') -RepositoryRoot $script:repository -FixtureRoot $fixture -Scenario $Scenario 2>&1)
		$workerExit = $LASTEXITCODE
		$records = @($output | Where-Object { "$_".StartsWith('PACKAGING_RESULT:') })
		$records | Should -HaveCount 1 -Because ($output -join "`n")
		$result = $records[0].ToString().Substring('PACKAGING_RESULT:'.Length) | ConvertFrom-Json
		$workerExit | Should -Be 0 -Because $result.HarnessError
		$result.Complete | Should -BeTrue
		$result.OutsideSurvived | Should -BeTrue
		$result.PesterCalls | Should -Be 0
		$result.GalleryCalls | Should -Be 0
		$result
	}
}

Describe 'Source-only build and staging acceptance (unavailable in staged distributions)' -Skip:(-not $script:hasPackagingSource) {
	It '<Scenario> publishes exactly two intact bundles' -ForEach @(@{ Scenario = 'CleanBuild' }, @{ Scenario = 'ReusedBuild' }) {
		$result = Invoke-PackagingWorker $Scenario
		$result.Error | Should -BeNullOrEmpty
		@($result.PublishCalls) | Should -HaveCount 2
		($result.PublishCalls.Rid | Sort-Object) -join ',' | Should -Be 'linux-x64,win-x64'
		$result.SourceRids -join ',' | Should -Be 'linux-x64,win-x64'
		foreach ($rid in @('win-x64', 'linux-x64')) {
			foreach ($file in @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll', 'fixture-native.bin', 'fixture-culture/resource.bin')) {
				$result.SourceFiles.Path | Should -Contain "$rid/$file"
			}
		}
		$result.SourceFiles.Path | Should -Not -Contain 'win-x64/old-source.txt'
	}

	It '<Scenario> stages only retained assets without nested publish output' -ForEach @(@{ Scenario = 'CleanStage' }, @{ Scenario = 'StandaloneStage' }) {
		$result = Invoke-PackagingWorker $Scenario
		$result.Error | Should -BeNullOrEmpty
		$result.StageRids -join ',' | Should -Be 'linux-x64,win-x64'
		@($result.PublishCalls) | Should -HaveCount 0
		$result.PreviousStageSurvived | Should -BeFalse
		@($result.StageFiles.Path | Where-Object { $_ -match '/publish/' }) | Should -HaveCount 0
		foreach ($asset in $result.SourceFiles | Where-Object { $_.Path -match '^(win|linux)-x64/' -and $_.Path -notmatch '/publish/' }) {
			$staged = @($result.StageFiles | Where-Object Path -EQ $asset.Path)
			$staged | Should -HaveCount 1
			$staged[0].Hash | Should -Be $asset.Hash
		}
		if ($Scenario -eq 'StandaloneStage') {
			$result.SourceRids | Should -Contain 'osx-x64'
		}
	}

	It 'rejects <Scenario> with an actionable failure' -ForEach @(
		@{ Scenario = 'PublishFailure'; Message = 'dotnet publish failed.*win-x64' }
		@{ Scenario = 'MissingPublished'; Message = 'Missing published dependency.*ScriptDom.*win-x64' }
		@{ Scenario = 'CopyFailure'; Message = 'Controlled copy failure' }
		@{ Scenario = 'MissingCopied'; Message = 'Missing copied dependency.*ScriptDom.*win-x64' }
		@{ Scenario = 'StageCopyFailure'; Message = 'Controlled copy failure' }
		@{ Scenario = 'MissingStaged'; Message = 'Release validation failed.*win-x64' }
		@{ Scenario = 'UnexpectedSource'; Message = 'Unexpected.*runtime.*director' }
		@{ Scenario = 'UnexpectedStage'; Message = 'Unexpected.*runtime.*director' }
		@{ Scenario = 'UnsafeBuild'; Message = 'Refusing to clean unexpected dependency path' }
		@{ Scenario = 'UnsafeObsolete'; Message = 'Refusing to clean unexpected obsolete dependency path' }
		@{ Scenario = 'UnsafeStage'; Message = 'Refusing to clean unexpected release path' }
	) {
		$result = Invoke-PackagingWorker $Scenario
		$result.Error | Should -Match $Message
		if ($Scenario -eq 'UnexpectedSource') {
			$result.UnexpectedSourceSurvived | Should -BeTrue
		}
	}

	It 'preserves the previous stage when a retained source library is missing' {
		$result = Invoke-PackagingWorker MissingSource
		$result.Error | Should -Match 'Missing required path.*|Cannot create the release package'
		$result.PreviousStageSurvived | Should -BeTrue
	}
}
