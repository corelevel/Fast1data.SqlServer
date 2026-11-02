BeforeAll {
	$script:distributionRoot = Split-Path -Parent $PSScriptRoot
	function Invoke-LoaderWorker {
		param ([string]$Scenario = 'Direct', [switch]$Copy, [switch]$Instrument, [string]$FaultPath, [string]$FaultKind = 'Missing', [string]$Consumer = 'Root')
		$root = $script:distributionRoot
		if ($Copy) {
			$root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
			Copy-Item -LiteralPath $script:distributionRoot -Destination $root -Recurse
			$null = New-Item -Path (Join-Path $root '.loader-test-copy') -ItemType File
		}
		$arguments = @('-NoLogo', '-NoProfile', '-File', (Join-Path $root 'tests/fixtures/Invoke-ModuleLoaderScenario.ps1'), '-DistributionRoot', $root, '-Scenario', $Scenario, '-Consumer', $Consumer)
		if ($Instrument) {
			$arguments += '-Instrument'
		}
		if ($FaultPath) {
			$arguments += @('-FaultPath', $FaultPath, '-FaultKind', $FaultKind)
		}
		Push-Location $TestDrive
		try {
			$output = @(& (Join-Path $PSHOME 'pwsh') @arguments 2>&1)
			$workerExit = $LASTEXITCODE
		}
		finally {
			Pop-Location
		}
		$records = @($output | Where-Object { "$_".StartsWith('MODULE_LOADER_RESULT:') })
		$records | Should -HaveCount 1 -Because ($output -join "`n")
		$result = $records[0].ToString().Substring('MODULE_LOADER_RESULT:'.Length) | ConvertFrom-Json
		$workerExit | Should -Be 0 -Because ($result.Errors -join "`n")
		$result.Complete | Should -BeTrue
		$result.Root | Should -Be $root
		$result.Scenario | Should -Be $Scenario
		Write-Information ('MODULE_LOADER_OBSERVATION:' + ($result | ConvertTo-Json -Depth 10 -Compress)) -InformationAction Continue
		$result
	}
}

Describe 'Explicit dependency boundaries' -Tag US2 {
	It 'accounts for the complete 23-file inventory through designated loaders' {
		$selection = @{
			'Fast1data.SqlServer.psm1' = @('private/shared/GenericSqlParam.psm1', 'private/shared/Get-RuntimeIdentifier.ps1', 'private/shared/Import-SqlClientLib.ps1', 'private/shared/Load.ps1', 'private/audit/Get-ImportState.ps1', 'private/audit/Get-SqlAuditFile.ps1', 'private/audit/Get-SqlAuditFileEntry.ps1', 'private/audit/Import-SqlAuditFile.ps1', 'private/migration/Get-FileChecksum.ps1', 'private/migration/Get-RelativePath.ps1', 'private/migration/Get-Executed.ps1', 'private/migration/Set-Executed.ps1', 'private/migration/Resolve-MigrationPhase.ps1', 'private/migration/Invoke-Migration.ps1', 'private/archiving/Load.ps1', 'private/archiving/Invoke-ArchivingProcess.ps1')
			'private/shared/Load.ps1' = @('GenericSqlCleanup.ps1', 'GenericSqlQuery.ps1', 'Write-LogMessage.ps1')
			'private/archiving/Load.ps1' = @('ArchivingModel.psm1')
			'private/archiving/ArchivingModel.psm1' = @('../shared/GenericSqlParam.psm1', 'Metadata.psm1', '../shared/Load.ps1', 'Get-DelayIntervalInSecond.ps1', 'Compare-Column.ps1')
		}
		$selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		foreach ($loader in $selection.Keys) {
			$loaderPath = Join-Path $script:distributionRoot $loader
			$code = (Get-Content -LiteralPath $loaderPath -Raw) -replace '\\', '/'
			$code | Should -Not -Match '-Recurse|\$privateScripts|-notin'
			foreach ($relative in $selection[$loader]) {
				$code | Should -Match ([regex]::Escape($relative))
				$null = $selected.Add([System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $loaderPath) $relative)))
			}
		}
		$inventory = @(Get-ChildItem -LiteralPath (Join-Path $script:distributionRoot 'private') -Recurse -File)
		$inventory | Should -HaveCount 23
		$selected.Count | Should -Be 23
		foreach ($file in $inventory) {
			$selected.Contains($file.FullName) | Should -BeTrue -Because $file.FullName
		}
	}

	It 'keeps declaration staging inert and dependency assembly out of ordinary behavior' {
		$tokens = $null
		$parseErrors = $null
		$declaration = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:distributionRoot 'private/archiving/Load.ps1'), [ref]$tokens, [ref]$parseErrors)
		$parseErrors | Should -BeNullOrEmpty
		@($declaration.UsingStatements) | Should -HaveCount 1
		$declaration.UsingStatements[0].Extent.Text | Should -Be 'using module ./ArchivingModel.psm1'
		@($declaration.EndBlock.Statements) | Should -HaveCount 0
		foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:distributionRoot 'private') -Recurse -Filter '*.ps1' | Where-Object Name -NE 'Load.ps1') {
			$ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
			$parseErrors | Should -BeNullOrEmpty
			@($ast.UsingStatements) | Should -HaveCount 0 -Because $file.Name
			$assembly = @($ast.FindAll({
				param ($Node)
				$Node -is [System.Management.Automation.Language.CommandAst] -and ($Node.InvocationOperator -eq 'Dot' -or $Node.GetCommandName() -in @('Import-Module', 'Invoke-Expression'))
			}, $true))
			$assembly | Should -HaveCount 0 -Because $file.Name
		}
	}

	It '<Scenario> imports from an unrelated directory with bootstrap before behavior' -ForEach @(@{ Scenario = 'Manifest' }, @{ Scenario = 'Sentinel' }, @{ Scenario = 'Reuse' }) {
		$result = Invoke-LoaderWorker -Scenario $Scenario -Copy -Instrument
		$result.PublicCommands | Should -HaveCount 3
	}

	It '<Consumer> rejects <FaultKind> dependency <FaultPath>' -ForEach @(
		foreach ($path in @('private/shared/GenericSqlCleanup.ps1', 'private/shared/GenericSqlQuery.ps1', 'private/shared/Write-LogMessage.ps1', 'private/migration/Get-FileChecksum.ps1', 'private/migration/Get-RelativePath.ps1', 'private/shared/Load.ps1', 'private/archiving/Load.ps1', 'private/shared/GenericSqlParam.psm1', 'private/archiving/Metadata.psm1', 'private/archiving/ArchivingModel.psm1', 'private/shared/Get-RuntimeIdentifier.ps1', 'private/shared/Import-SqlClientLib.ps1', 'private/audit/Get-ImportState.ps1', 'private/audit/Get-SqlAuditFile.ps1', 'private/audit/Get-SqlAuditFileEntry.ps1', 'private/audit/Import-SqlAuditFile.ps1', 'private/migration/Get-Executed.ps1', 'private/migration/Set-Executed.ps1', 'private/migration/Resolve-MigrationPhase.ps1', 'private/migration/Invoke-Migration.ps1', 'private/archiving/Invoke-ArchivingProcess.ps1', 'private/archiving/Get-DelayIntervalInSecond.ps1', 'private/archiving/Compare-Column.ps1', 'SqlClient')) {
			@{ FaultPath = $path; FaultKind = 'Missing'; Consumer = 'Root' }
		}
		foreach ($path in @('SqlClient', 'private/shared/GenericSqlQuery.ps1', 'private/shared/Load.ps1', 'private/archiving/Load.ps1', 'private/shared/GenericSqlParam.psm1', 'private/archiving/Metadata.psm1', 'private/archiving/ArchivingModel.psm1')) {
			@{ FaultPath = $path; FaultKind = 'Corrupt'; Consumer = 'Root' }
		}
		foreach ($path in @('private/shared/Load.ps1', 'private/archiving/Get-DelayIntervalInSecond.ps1', 'private/archiving/Compare-Column.ps1', 'private/archiving/Metadata.psm1')) {
			@{ FaultPath = $path; FaultKind = 'Missing'; Consumer = 'Model' }
		}
		foreach ($consumer in @('Root', 'Model')) {
			@{ FaultPath = 'private/shared/GenericSqlQuery.ps1'; FaultKind = 'RuntimeError'; Consumer = $consumer }
		}
	) {
		$result = Invoke-LoaderWorker -Scenario Fault -Copy -FaultPath $FaultPath -FaultKind $FaultKind -Consumer $Consumer
		$result.OriginalError | Should -Not -BeNullOrEmpty
		$result.PublicCommands | Should -HaveCount 0
	}
}

Describe 'Fresh-process loader harness' -Tag US3 {
	It 'reports a cold no-fault worker completely' {
		$result = Invoke-LoaderWorker
		$result.PublicCommands | Should -HaveCount 3
	}
}

Describe 'One shared behavior list and independent consumers' -Tag US1 {
	It 'selects exactly the three shared files in their required order' {
		$path = Join-Path $script:distributionRoot 'private/shared/Load.ps1'
		$tokens = $null
		$parseErrors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
		$parseErrors | Should -BeNullOrEmpty
		$commands = @($ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true))
		$commands | Should -HaveCount 3
		$expected = @('GenericSqlCleanup.ps1', 'GenericSqlQuery.ps1', 'Write-LogMessage.ps1')
		for ($i = 0; $i -lt $commands.Count; $i++) {
			$commands[$i].InvocationOperator | Should -Be 'Dot'
			$commands[$i].CommandElements[0].Extent.Text | Should -Be ('"$PSScriptRoot/' + $expected[$i] + '"')
		}
		foreach ($relative in @('Fast1data.SqlServer.psm1', 'private/archiving/ArchivingModel.psm1')) {
			$code = Get-Content -LiteralPath (Join-Path $script:distributionRoot $relative) -Raw
			$code | Should -Match '\.\s+"\$PSScriptRoot/.*shared/Load\.ps1"'
			foreach ($file in $expected) {
				$code | Should -Not -Match ([regex]::Escape($file))
			}
		}
	}

	It '<Scenario> executes the list twice without initialization output' -ForEach @(@{ Scenario = 'Direct' }, @{ Scenario = 'ModelFirst' }) {
		$result = Invoke-LoaderWorker -Scenario $Scenario -Copy -Instrument
		$result.Owners | Should -HaveCount 12
	}

	It 'extends both consumers by editing only a disposable shared list' {
		$result = Invoke-LoaderWorker -Scenario Extension -Copy -Instrument
		$result.Owners | Should -HaveCount 12
	}
}
