BeforeAll {
	. (Join-Path $PSScriptRoot 'Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

Describe 'Delegated migration history' {
	BeforeEach {
		InModuleScope Fast1data.SqlServer -Parameters @{ Fixture = (Join-Path $PSScriptRoot 'GenericSqlQuery.Doubles.ps1') } {
			. $Fixture
			$script:historyTest = Get-GenericSqlTestExecution -Results @(@{
				Names = @('script_name', 'checksum')
				Rows = @(@{ Values = @('Folder\UP.sql', 'abc') }, @{ Values = @('Other/Mixed.sql', 'def') })
			})
			Update-TypeData -TypeName Microsoft.Data.SqlClient.SqlConnection -MemberName Open -MemberType ScriptMethod -Force -Value {
				$historyState = & (Get-Module Fast1data.SqlServer) { $script:historyTest.State }
				$historyState.Events.Add('Connection.Open')
				if ($historyState.FailAt -eq 'Open') {
					throw 'controlled Open failure'
				}
				$this | Add-Member -NotePropertyName HistoryOpen -NotePropertyValue $true
			}
			Update-TypeData -TypeName Microsoft.Data.SqlClient.SqlConnection -MemberName Dispose -MemberType ScriptMethod -Force -Value {
				$historyState = & (Get-Module Fast1data.SqlServer) { $script:historyTest.State }
				$historyState.Events.Add('Connection.Dispose')
				$this.psbase.Dispose()
				if ('Connection' -in $historyState.FailDisposal) {
					throw 'controlled Connection disposal failure'
				}
			}
			Mock Get-GenericSqlCommand {
				$SqlConn.HistoryOpen | Should -BeTrue
				$script:historyTest.Command.CommandText = $Query
				$script:historyTest.Command
			}
		}
	}
	AfterEach {
		Remove-TypeData -TypeName Microsoft.Data.SqlClient.SqlConnection
		InModuleScope Fast1data.SqlServer {
			$script:historyTest.Command.psbase.Dispose()
			$script:historyTest.Connection.psbase.Dispose()
		}
	}

	It 'retains mandatory private inputs and delegates the exact SELECT and phase descriptor' {
		InModuleScope Fast1data.SqlServer {
			foreach ($name in @('ConnStr', 'Phase')) {
				@((Get-Command Get-Executed).Parameters[$name].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
			}
			Mock New-Fast1GenericSqlParam { [GenericSqlParam]@{ Type = $Type; Size = $Size; Value = $Value } }
			Mock Invoke-Fast1GenericSqlQueryReader {
				$SqlConn.HistoryOpen | Should -BeTrue
				$CommandType | Should -Be 'Text'
				$Query.Replace("`r`n", "`n").Trim() | Should -Be "set nocount on`nselect script_name, [checksum]`nfrom dbo.fast1_migration_history`nwhere phase = @phase"
				$Parameters.Keys -join ',' | Should -Be 'phase'
				$Parameters.phase.Type | Should -Be 'NVarChar'
				$Parameters.phase.Size | Should -Be 32
				$Parameters.phase.Value | Should -Be 'phase01'
				[pscustomobject][ordered]@{ script_name = 'Folder\UP.sql'; checksum = 'abc' }
			}
			$rows = @(Get-Executed -ConnStr 'Server=controlled' -Phase phase01)
			$rows | Should -HaveCount 1
			$rows[0].script_name | Should -BeExactly 'Folder\UP.sql'
			Should -Invoke New-Fast1GenericSqlParam -Times 1 -Exactly -ParameterFilter { $Type -eq 'NVarChar' -and $Size -eq 32 -and $Value -eq 'phase01' }
			Should -Invoke Invoke-Fast1GenericSqlQueryReader -Times 1 -Exactly
			$script:historyTest.State.Events -join ',' | Should -Be 'Connection.Open,Connection.Dispose'
		}
	}

	It 'streams exact persisted keys and checksums through real rows (Empty=<Empty>, Truncate=<Truncate>)' -ForEach @(
		@{ Empty = $false; Truncate = $false }
		@{ Empty = $true; Truncate = $false }
		@{ Empty = $false; Truncate = $true }
	) {
		InModuleScope Fast1data.SqlServer -Parameters @{ Empty = $Empty; Truncate = $Truncate } {
			if ($Empty) {
				$script:historyTest.State.Results[0].Rows = @()
			}
			$seen = [System.Collections.Generic.List[object]]::new()
			Get-Executed -ConnStr 'Server=controlled' -Phase phase01 | ForEach-Object {
				$script:historyTest.State.ReadCount | Should -Be ($seen.Count + 1)
				$seen.Add($_)
				$_
			} | Select-Object -First $(if ($Truncate) {
				1
			}
			else {
				100
			}) | Out-Null
			if ($Empty) {
				$seen | Should -HaveCount 0
			}
			else {
				$seen[0].PSObject.Properties.Name -join ',' | Should -Be 'script_name,checksum'
				$seen[0].script_name | Should -BeExactly 'Folder\UP.sql'
				$seen[0].checksum | Should -BeExactly 'abc'
				if ($Truncate) {
					$seen | Should -HaveCount 1
					$script:historyTest.State.ReadCount | Should -Be 1
				}
				else {
					$seen[1].script_name | Should -BeExactly 'Other/Mixed.sql'
					$seen[1].checksum | Should -BeExactly 'def'
				}
			}
			$script:historyTest.State.Events[-3..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose,Connection.Dispose'
		}
	}

	It 'reads history under ambient WhatIf so migration preview still validates persisted checksums' {
		InModuleScope Fast1data.SqlServer {
			$WhatIfPreference = $true
			$rows = @(Get-Executed -ConnStr 'Server=controlled' -Phase phase01)
			$rows | Should -HaveCount 2
			$script:historyTest.Command.Parameters['@phase'].Value | Should -Be 'phase01'
			$script:historyTest.State.Events[-3..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose,Connection.Dispose'
		}
	}

	It 'preserves <Failure> errors and combined nested cleanup details' -ForEach @(
		foreach ($failure in @('Open', 'ExecuteReader', 'GetName', 'Read', 'LateRead', 'CleanupOnly', 'ConnectionString')) {
			@{ Failure = $failure }
		}
	) {
		InModuleScope Fast1data.SqlServer -Parameters @{ Failure = $Failure } {
			$script:historyTest.State.FailDisposal = @('Reader', 'Command', 'Connection')
			$connStr = 'Server=controlled'
			if ($Failure -eq 'ConnectionString') {
				$connStr = 'InvalidKeyword=value'
			}
			elseif ($Failure -eq 'LateRead') {
				$script:historyTest.State.FailRead = 2
			}
			elseif ($Failure -ne 'CleanupOnly') {
				$script:historyTest.State.FailAt = $Failure
			}
			$seen = [System.Collections.Generic.List[object]]::new()
			$caught = $null
			try {
				Get-Executed -ConnStr $connStr -Phase phase01 | ForEach-Object { $seen.Add($_) }
			}
			catch {
				$caught = $_
			}
			$caught | Should -Not -BeNullOrEmpty
			$expected = 'Reader,Command,Connection'
			if ($Failure -in @('Open', 'ConnectionString')) {
				$expected = 'Connection'
			}
			elseif ($Failure -eq 'ExecuteReader') {
				$expected = 'Command,Connection'
			}
			if ($Failure -eq 'LateRead') {
				$seen | Should -HaveCount 1
				$caught.Exception.Message | Should -Match 'controlled Read failure'
			}
			elseif ($Failure -eq 'CleanupOnly') {
				$caught.Exception.Message | Should -Match 'controlled Reader disposal failure'
			}
			elseif ($Failure -ne 'ConnectionString') {
				$caught.Exception.Message | Should -Match "controlled $Failure failure"
			}
			$entries = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$entries.ResourceRole -join ',' | Should -Be $expected
			($entries | ConvertTo-Json) | Should -Not -Match 'controlled|InvalidKeyword|Server=|phase01'
			$script:historyTest.State.Events[-1] | Should -Be 'Connection.Dispose'
		}
	}
}
