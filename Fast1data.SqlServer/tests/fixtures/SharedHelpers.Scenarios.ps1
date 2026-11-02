param ($DistributionRoot, $OperationOrder, $OwnerBefore)

if (-not $DistributionRoot -or $OperationOrder -notin @('ARM', 'AMR', 'RAM', 'RMA', 'MAR', 'MRA') -or $null -eq $OwnerBefore) {
	throw 'The scenario requires a selected root, operation order, and pre-import owner.'
}

BeforeAll {
	$rootModule = Get-Module Fast1data.SqlServer
	$rootModule.ModuleBase | Should -Be $DistributionRoot
}

Describe 'Real operational logging in one session' {
	BeforeAll {
		$phaseRoot = Join-Path $TestDrive 'migration'
		$null = New-Item -ItemType Directory -Path (Join-Path $phaseRoot 'empty') -Force
		'{"empty":{"scripts":[]}}' | Set-Content (Join-Path $phaseRoot 'migration.json')
		Mock Get-SqlAuditFile -ModuleName Fast1data.SqlServer { @() }
		Mock Get-Executed -ModuleName Fast1data.SqlServer { @() }
		Mock Get-ArchivingConnection -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
			param ($ConnectionString)
			$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($ConnectionString)
			$connection | Add-Member -MemberType ScriptMethod -Name Open -Force -Value {}
			$connection
		}
		Mock Get-GenericSqlCommand -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
			param ($Query, $SqlConn)
			$command = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn)
			$command | Add-Member -MemberType ScriptMethod -Name ExecuteScalar -Force -Value { 'controlled' }
			$command
		}
		Mock Get-ArchivingCommand -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
			param ($Query, $Connection)
			$data = [System.Data.DataTable]::new()
			if ($Query -eq 'dbo.stp_GetTableGroup') {
				$values = [ordered]@{ TableGroupId = 1; SrcServerName = 'controlled'; SrcDatabaseName = 'source'; SrcConnOptions = ''; DstServerName = 'controlled'; DstDatabaseName = 'destination'; DstConnOptions = ''; DisableFK = $false }
				foreach ($key in $values.Keys) {
					$null = $data.Columns.Add($key, [object])
				}
				$row = $data.NewRow()
				foreach ($key in $values.Keys) {
					$row[$key] = $values[$key]
				}
				$data.Rows.Add($row)
			}
			$command = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $Connection)
			$command | Add-Member -NotePropertyName ControlledData -NotePropertyValue $data
			$command | Add-Member -MemberType ScriptMethod -Name ExecuteReader -Force -Value { return ,$this.ControlledData.CreateDataReader() }
			$command
		}
		function Invoke-ControlledOperation {
			param ([hashtable]$Override, [bool]$Enabled)
			foreach ($operation in $OperationOrder.ToCharArray()) {
				$records = @(switch ($operation) {
					'A' {
						Invoke-Fast1Audit -ConnStr 'unused' -Folder 'unused' @Override 4>&1
					}
					'R' {
						Invoke-Fast1Archiving -ConnStr 'Server=controlled' -GroupName 'empty' @Override 4>&1
					}
					'M' {
						Invoke-Fast1Migration -ConnStr 'unused' -BasePath $phaseRoot -Phase 'empty' @Override 4>&1
					}
				})
				$expected = @()
				if ($Enabled) {
					$expected = @(switch ($operation) {
						'A' {
							'No audit files found in unused'
						}
						'R' {
							'Archive group (empty) found'
							'No tables found for the specified table group (empty)'
						}
						'M' {
							'Nothing to run'
						}
					})
				}
				$records.Count | Should -Be @($expected).Count -Because "operation $operation"
				for ($i = 0; $i -lt $records.Count; $i++) {
					$records[$i] | Should -BeOfType ([System.Management.Automation.VerboseRecord])
					$records[$i].Message | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\] \[Verbose\] '
					($records[$i].Message -replace '^\[[^\]]+\] \[Verbose\] ', '') | Should -Be $expected[$i]
				}
			}
		}
	}

	It 'retains literal class imports, parameterless execution and the scoped overload' {
		& (Join-Path $PSScriptRoot 'SharedHelpers.Classes.ps1')
	}

	It 'retains migration warnings with verbose suppressed and does not emit success output' {
		$records = @(Invoke-Fast1Migration -ConnStr unused -BasePath $phaseRoot -Phase empty -IgnoreScripts unknown.sql -Verbose:$false -WarningAction Continue 3>&1)
		$records | Should -HaveCount 1
		$records[0] | Should -BeOfType ([System.Management.Automation.WarningRecord])
		$records[0].Message | Should -Match '\[Warning\].*unknown.sql'
	}

	It 'honors all ambient/explicit combinations and sequential changes without leaking preferences' {
		$original = $VerbosePreference
		try {
			foreach ($ambient in @('SilentlyContinue', 'Continue')) {
				$global:VerbosePreference = [System.Management.Automation.ActionPreference]$ambient
				foreach ($explicit in @('true', 'false', 'absent', 'false', 'true')) {
					$override = @{}
					$enabled = $ambient -eq 'Continue'
					if ($explicit -ne 'absent') {
						$enabled = $explicit -eq 'true'
						$override.Verbose = $enabled
					}
					Invoke-ControlledOperation -Override $override -Enabled $enabled
					$global:VerbosePreference | Should -Be $ambient
				}
			}
		}
		finally {
			$global:VerbosePreference = $original
		}
	}

	It 'honors all function-local ambient and explicit settings' {
		& $rootModule {
			param ($PhaseRoot)
			foreach ($ambient in @('Continue', 'SilentlyContinue')) {
				$VerbosePreference = $ambient
				foreach ($explicit in @('true', 'false', 'absent')) {
					$override = @{}
					$enabled = $ambient -eq 'Continue'
					if ($explicit -ne 'absent') {
						$enabled = $explicit -eq 'true'
						$override.Verbose = $enabled
					}
					@(Invoke-Fast1Audit -ConnStr unused -Folder unused @override 4>&1).Count | Should -Be ([int]$enabled)
					@(Invoke-Fast1Archiving -ConnStr 'Server=controlled' -GroupName empty @override 4>&1).Count | Should -Be (2 * [int]$enabled)
					@(Invoke-Fast1Migration -ConnStr unused -BasePath $PhaseRoot -Phase empty @override 4>&1).Count | Should -Be ([int]$enabled)
					$VerbosePreference | Should -Be $ambient
				}
			}
		} $phaseRoot
	}

	It 'preserves caller preferences after failures in every operation and verbosity combination' {
		Mock Get-SqlAuditFile -ModuleName Fast1data.SqlServer { throw 'controlled failure' }
		Mock Get-Executed -ModuleName Fast1data.SqlServer { throw 'controlled failure' }
		Mock Get-ArchivingConnection -ModuleName 'Fast1data.SqlServer/ArchivingModel' { throw 'controlled failure' }
		$original = $global:VerbosePreference
		$warningBefore = $WarningPreference
		try {
			foreach ($ambient in @('Continue', 'SilentlyContinue')) {
				$global:VerbosePreference = $ambient
				foreach ($explicit in @('true', 'false', 'absent')) {
					$override = @{}
					if ($explicit -ne 'absent') {
						$override.Verbose = $explicit -eq 'true'
					}
					{ Invoke-Fast1Audit -ConnStr unused -Folder unused @override } | Should -Throw '*controlled failure*'
					{ Invoke-Fast1Archiving -ConnStr unused -GroupName empty @override -WarningAction SilentlyContinue } | Should -Throw '*controlled failure*'
					{ Invoke-Fast1Migration -ConnStr unused -BasePath $phaseRoot -Phase empty @override } | Should -Throw '*controlled failure*'
					$global:VerbosePreference | Should -Be $ambient
					$WarningPreference | Should -Be $warningBefore
				}
			}
		}
		finally {
			$global:VerbosePreference = $original
		}
	}

	It 'retains warning records and preferences on archiving failure with verbosity suppressed' {
		Mock Get-ArchivingConnection -ModuleName 'Fast1data.SqlServer/ArchivingModel' { throw 'controlled initialization failure' }
		$before = $VerbosePreference
		$warnings = [System.Collections.Generic.List[object]]::new()
		$caught = $null
		try {
			Invoke-Fast1Archiving -ConnStr unused -GroupName empty -Verbose:$false -WarningAction Continue 3>&1 | ForEach-Object { $warnings.Add($_) }
		}
		catch {
			$caught = $_
		}
		$caught.Exception.Message | Should -Match 'controlled initialization failure'
		$warnings | Should -HaveCount 1
		$warnings[0] | Should -BeOfType ([System.Management.Automation.WarningRecord])
		$warnings[0].Message | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\] \[Warning\] Archiving execution failed for group \(empty\);'
		$VerbosePreference | Should -Be $before
	}
}

Describe 'Internal ownership and unchanged distribution contract' {
	It 'retains separate defining session states and selected-root paths for every helper' {
		$shared = @('Write-LogMessage', 'Get-GenericSqlCommand', 'Invoke-GenericSqlQuery', 'Close-GenericSqlResource', 'Add-GenericSqlCleanupFailure', 'Get-GenericSqlCleanupFailure')
		$rootOnly = @('Get-FileChecksum', 'Get-RelativePath', 'Get-RuntimeIdentifier', 'Import-SqlClientLib', 'Invoke-ArchivingProcess', 'Get-SqlAuditFile', 'Get-SqlAuditFileEntry', 'Import-SqlAuditFile', 'Get-ImportState', 'Get-Executed', 'Set-Executed', 'Invoke-Migration', 'Resolve-MigrationPhase')
		$modelOnly = @('Compare-Column', 'Get-DelayIntervalInSecond', 'Get-ArchivingConnection', 'Get-ArchivingCommand', 'Get-ArchivingTable', 'Get-ArchivingBulkCopy', 'Get-ArchivingServerIdentity', 'ConvertTo-ArchivingIdentifier', 'Invoke-ArchivingConstraintAction')
		$model = Get-Module ArchivingModel
		foreach ($entry in @(@{ Module = $rootModule; Names = $shared + $rootOnly }, @{ Module = $model; Names = $shared + $modelOnly })) {
			foreach ($name in $entry.Names) {
				$command = & $entry.Module { param ($Name) Get-Command $Name } $name
				[object]::ReferenceEquals($command.Module, $entry.Module) | Should -BeTrue -Because "$name must retain its defining module"
				[object]::ReferenceEquals($command.Module.SessionState, $entry.Module.SessionState) | Should -BeTrue
				$command.ScriptBlock.File.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar) | Should -BeTrue
			}
		}
		[object]::ReferenceEquals($OwnerBefore, (& $rootModule { (Get-Command Write-LogMessage).Module })) | Should -BeTrue
		foreach ($name in $modelOnly) {
			& $rootModule { param ($Name) Get-Command $Name -ErrorAction SilentlyContinue } $name | Should -BeNullOrEmpty
		}
		foreach ($name in $rootOnly) {
			$command = & $model { param ($Name) Get-Command $Name -ErrorAction SilentlyContinue } $name
			[object]::ReferenceEquals($command.Module, $model) | Should -BeFalse
		}
		foreach ($module in Get-Module -All | Where-Object Name -In @('ArchivingModel', 'Metadata', 'GenericSqlParam')) {
			$module.ExportedCommands.Count | Should -Be 0
			$module.Path.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar) | Should -BeTrue
		}
	}

	It 'matches the fixed pre-change public metadata and runtime assets' {
		. (Join-Path $PSScriptRoot 'Get-SharedHelperPublicContract.ps1')
		$expected = Get-Content (Join-Path $PSScriptRoot 'SharedHelpers.PublicContract.json') -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
		$actual = Get-SharedHelperPublicContract -DistributionRoot $DistributionRoot | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
		$actual | Should -Be $expected
		($rootModule.ExportedFunctions.Keys | Sort-Object) -join ',' | Should -Be 'Invoke-Fast1Archiving,Invoke-Fast1Audit,Invoke-Fast1Migration'
		$rootModule.ExportedAliases.Count | Should -Be 0
		$rootModule.ExportedVariables.Count | Should -Be 0
		$rootModule.ExportedCmdlets.Count | Should -Be 0
		foreach ($rid in @('win-x64', 'linux-x64', 'osx-x64')) {
			Test-Path (Join-Path $DistributionRoot "lib/$rid/Microsoft.Data.SqlClient.dll") | Should -BeTrue
		}
		[Microsoft.Data.SqlClient.SqlConnection].Assembly.Location.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar) | Should -BeTrue
	}
}
