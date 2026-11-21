BeforeAll {
	. (Join-Path $PSScriptRoot 'Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

Describe 'Shared parameter binding and scalar defaults in <Owner>' -ForEach @(@{ Owner = 'Fast1data.SqlServer' }, @{ Owner = 'ArchivingModel' }) {
	BeforeEach {
		InModuleScope $Owner -Parameters @{ Fixture = (Join-Path $PSScriptRoot 'GenericSqlQuery.Doubles.ps1') } {
			. $Fixture
			$script:bindingTest = Get-GenericSqlTestExecution
			Mock Get-GenericSqlCommand { $script:bindingTest.Command }
		}
	}
	AfterEach {
		InModuleScope $Owner {
			$script:bindingTest.Command.psbase.Dispose()
			$script:bindingTest.Connection.psbase.Dispose()
		}
	}

	It 'distinguishes absent Type from explicit BigInt zero without changing descriptor identity' {
		InModuleScope $Owner {
			[GenericSqlParam].GetProperty('Type').PropertyType | Should -Be ([Nullable[System.Data.SqlDbType]])
			($null -eq [GenericSqlParam]::new().Type) | Should -BeTrue
			$descriptor = [GenericSqlParam]@{ Type = 0; Value = 42 }
			Invoke-Fast1GenericSqlQuery -SqlConn $script:bindingTest.Connection -Query unused -Parameters @{ id = $descriptor } -Scalar | Should -Be 42
			$script:bindingTest.Command.Parameters['@id'].SqlDbType | Should -Be 'BigInt'
			$script:bindingTest.Command.Parameters['@id'].Value | Should -Be 42
		}
	}

	It 'binds nulls and native binary arrays without success output or metadata coercion' {
		InModuleScope $Owner {
			foreach ($length in @(0, 1, 3)) {
				$script:bindingTest.Command.Parameters.Clear()
				$payload = [byte[]]::new($length)
				$output = @(Invoke-Fast1GenericSqlQuery -SqlConn $script:bindingTest.Connection -Query unused -Parameters @{
					payload = [GenericSqlParam]@{ Type = 'VarBinary'; Value = $payload }
					nothing = [GenericSqlParam]@{ Type = 'NVarChar'; Size = 12 }
					amount = [GenericSqlParam]@{ Type = 'Decimal'; Value = [decimal]1.25; Precision = 0; Scale = 0 }
				})
				$output | Should -HaveCount 0
				[object]::ReferenceEquals($payload, $script:bindingTest.Command.Parameters['@payload'].Value) | Should -BeTrue
				$script:bindingTest.Command.Parameters['@nothing'].Value | Should -Be ([DBNull]::Value)
				$script:bindingTest.Command.Parameters['@nothing'].Size | Should -Be 12
				$script:bindingTest.Command.Parameters['@amount'].Scale | Should -Be 2
			}
			$script:bindingTest.Command.CommandTimeout | Should -Be 30
			$script:bindingTest.State.Events | Should -Not -Contain 'Connection.Open'
			$script:bindingTest.State.Events | Should -Not -Contain 'Connection.Dispose'
		}
	}

	It 'retains scalar first-cell provider results including null and DBNull' {
		InModuleScope $Owner {
			foreach ($value in @(42, $null, [DBNull]::Value)) {
				$script:bindingTest.State.ScalarValue = $value
				$actual = Invoke-Fast1GenericSqlQuery -SqlConn $script:bindingTest.Connection -Query unused -Scalar
				[object]::Equals($actual, $value) | Should -BeTrue
			}
		}
	}

	It 'surfaces a closed provider connection without opening or repairing it' {
		InModuleScope $Owner {
			$closed = [Microsoft.Data.SqlClient.SqlConnection]::new()
			try {
				Mock Get-GenericSqlCommand { [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn) }
				{ Invoke-Fast1GenericSqlQuery -SqlConn $closed -Query 'SELECT 1;' } | Should -Throw '*open*'
				$closed.State | Should -Be 'Closed'
				{ Invoke-Fast1GenericSqlQuery -SqlConn 'invalid' -Query unused } | Should -Throw
			}
			finally {
				$closed.Dispose()
			}
		}
	}
}

Describe 'Incremental row ownership in <Owner>' -Tag QueryRows -ForEach @(@{ Owner = 'Fast1data.SqlServer' }, @{ Owner = 'ArchivingModel' }) {
	BeforeEach {
		InModuleScope $Owner -Parameters @{ Fixture = (Join-Path $PSScriptRoot 'GenericSqlQuery.Doubles.ps1') } {
			. $Fixture
			$script:streamTest = Get-GenericSqlTestExecution
			Mock Get-GenericSqlCommand { $script:streamTest.Command }
		}
	}
	AfterEach {
		InModuleScope $Owner {
			$script:streamTest.Command.psbase.Dispose()
			$script:streamTest.Connection.psbase.Dispose()
		}
	}

	It 'delivers the first object before a second Read and retains it after a later failure' {
		InModuleScope $Owner {
			$script:streamTest.State.FailRead = 2
			$script:streamTest.State.FailDisposal = @('Reader', 'Command')
			$seen = [System.Collections.Generic.List[object]]::new()
			$caught = $null
			try {
				Invoke-Fast1GenericSqlQueryReader -SqlConn $script:streamTest.Connection -Query unused | ForEach-Object {
					$script:streamTest.State.ReadCount | Should -Be 1
					$script:streamTest.State.Events.Add('Output')
					$seen.Add($_)
				}
			}
			catch {
				$caught = $_
			}
			$seen | Should -HaveCount 1
			$seen[0].Id | Should -Be 1
			$caught.Exception.Message | Should -Match 'controlled Read failure'
			@(Get-GenericSqlCleanupFailure -ErrorRecord $caught).ResourceRole -join ',' | Should -Be 'Reader,Command'
			$script:streamTest.State.Events.IndexOf('Output') | Should -BeLessThan $script:streamTest.State.Events.IndexOf('Read:2')
			$script:streamTest.State.Events[-2..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose'
		}
	}

	It 'stops application reads and disposes owned resources on downstream truncation (CleanupFailure=<CleanupFailure>)' -ForEach @(@{ CleanupFailure = $false }, @{ CleanupFailure = $true }) {
		InModuleScope $Owner -Parameters @{ CleanupFailure = $CleanupFailure } {
			if ($CleanupFailure) {
				$script:streamTest.State.FailDisposal = @('Reader', 'Command')
				$script:stoppedCleanupError = $null
				$script:stoppedCleanupImplementation = (Get-Command Close-GenericSqlResource).ScriptBlock
				# Observe the actual cleanup throw before PowerShell suppresses it while stopping upstream.
				Mock Close-GenericSqlResource {
					try {
						& $script:stoppedCleanupImplementation -Resources $Resources -PrimaryError $PrimaryError
					}
					catch {
						$script:stoppedCleanupError = $_
						throw
					}
				}
			}
			$seen = [System.Collections.Generic.List[object]]::new()
			$caught = $null
			try {
				Invoke-Fast1GenericSqlQueryReader -SqlConn $script:streamTest.Connection -Query unused | ForEach-Object {
					$seen.Add($_)
					$_
				} | Select-Object -First 1 | Out-Null
			}
			catch {
				$caught = $_
			}
			$seen | Should -HaveCount 1
			if ($CleanupFailure) {
				$script:stoppedCleanupError.Exception.Message | Should -Match 'controlled Reader disposal failure'
				@(Get-GenericSqlCleanupFailure -ErrorRecord $script:stoppedCleanupError).ResourceRole -join ',' | Should -Be 'Reader,Command'
			}
			else {
				$caught | Should -BeNullOrEmpty
			}
			$script:streamTest.State.ReadCount | Should -Be 1
			$script:streamTest.State.Events[-2..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose'
			$script:streamTest.State.Events | Should -Not -Contain 'Connection.Dispose'
		}
	}

	It 'releases every created resource on <Operation> failure, preserving it over disposal errors' -ForEach @(
		foreach ($operation in @('Construction', 'Binding', 'ExecuteReader', 'NextResult', 'GetName', 'GetValue', 'Read')) {
			@{ Operation = $operation }
		}
	) {
		InModuleScope $Owner -Parameters @{ Operation = $Operation } {
			$script:streamTest.State.FailDisposal = @('Reader', 'Command')
			$parameters = @{}
			if ($Operation -eq 'Construction') {
				Mock Get-GenericSqlCommand { throw 'controlled Construction failure' }
			}
			elseif ($Operation -eq 'Binding') {
				$parameters.bad = 'invalid'
			}
			else {
				$script:streamTest.State.FailAt = $Operation
				if ($Operation -eq 'NextResult') {
					$script:streamTest.State.Results = @(@{ Names = @(); Rows = @() })
				}
			}
			$caught = $null
			try {
				Invoke-Fast1GenericSqlQueryReader -SqlConn $script:streamTest.Connection -Query unused -Parameters $parameters
			}
			catch {
				$caught = $_
			}
			$caught | Should -Not -BeNullOrEmpty
			if ($Operation -eq 'Binding') {
				$caught.Exception.Message | Should -Match 'must be of type GenericSqlParam'
			}
			else {
				$caught.Exception.Message | Should -Match "controlled $Operation failure"
			}
			$expected = @('Reader', 'Command')
			if ($Operation -in @('Binding', 'ExecuteReader')) {
				$expected = @('Command')
			}
			elseif ($Operation -eq 'Construction') {
				$expected = @()
			}
			$failures = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			@($failures | Select-Object -ExpandProperty ResourceRole) -join ',' | Should -Be ($expected -join ',')
			($failures | ConvertTo-Json) | Should -Not -Match 'controlled|Password|ConnectionString|unused'
			$script:streamTest.State.Events | Should -Not -Contain 'Connection.Dispose'
		}
	}

	It 'throws the first cleanup-only failure after attempting both disposals (Reader=<Reader>, Command=<Command>)' -ForEach @(
		@{ Reader = $true; Command = $false }
		@{ Reader = $false; Command = $true }
		@{ Reader = $true; Command = $true }
	) {
		InModuleScope $Owner -Parameters @{ Reader = $Reader; Command = $Command } {
			if ($Reader) {
				$script:streamTest.State.FailDisposal += 'Reader'
			}
			if ($Command) {
				$script:streamTest.State.FailDisposal += 'Command'
			}
			$caught = $null
			try {
				Invoke-Fast1GenericSqlQueryReader -SqlConn $script:streamTest.Connection -Query unused | Out-Null
			}
			catch {
				$caught = $_
			}
			$caught.Exception.Message | Should -Match 'controlled .* disposal failure'
			$entries = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$entries.Count | Should -Be ([int]$Reader + [int]$Command)
			$script:streamTest.State.Events[-2..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose'
		}
	}
}
