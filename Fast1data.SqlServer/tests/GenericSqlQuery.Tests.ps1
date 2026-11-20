BeforeAll {
	$script:distributionRoot = Split-Path -Parent $PSScriptRoot
	Import-Module (Join-Path $script:distributionRoot 'Fast1data.SqlServer.psd1')
}

Describe 'First tabular SQL result in <Owner>' -ForEach @(@{ Owner = 'Fast1data.SqlServer' }, @{ Owner = 'ArchivingModel' }) {
	BeforeAll {
		. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent $PSScriptRoot)
	}
	BeforeEach {
		InModuleScope $Owner -Parameters @{ Fixture = (Join-Path $PSScriptRoot 'fixtures/GenericSqlQuery.Doubles.ps1') } {
			. $Fixture
			$script:rowTest = Get-GenericSqlTestExecution
			Mock Get-GenericSqlCommand {
				$script:rowTest.Command.CommandText = $Query
				$script:rowTest.Command
			}
		}
	}
	AfterEach {
		InModuleScope $Owner {
			$script:rowTest.Command.psbase.Dispose()
			$script:rowTest.Connection.psbase.Dispose()
		}
	}

	It 'has the same inputs as scalar execution without an execution switch' {
		InModuleScope $Owner {
			$command = Get-Command Invoke-Fast1GenericSqlQueryReader -ErrorAction Stop
			$command.Parameters.Keys | Should -Contain 'SqlConn'
			$command.Parameters.Keys | Should -Contain 'Query'
			$command.Parameters.Keys | Should -Contain 'Parameters'
			$command.Parameters.Keys | Should -Contain 'CommandType'
			$command.Parameters.Keys | Should -Not -Contain 'Scalar'
			$command.Parameters.Keys | Should -Not -Contain 'Rows'
		}
	}

	It 'emits fresh independent ordered objects for each row and ignores later results' {
		InModuleScope $Owner {
			$script:rowTest.State.Results += @{ Names = @('Later'); Rows = @(@{ Values = @(99) }) }
			$rows = @(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:rowTest.Connection -Query 'controlled')
			$rows | Should -HaveCount 2
			$rows[0].Id | Should -Be 1
			$rows[1].Id | Should -Be 2
			[object]::ReferenceEquals($rows[0], $rows[1]) | Should -BeFalse
			$rows[0].Id = 100
			$rows[1].Id | Should -Be 2
			$script:rowTest.State.Events | Should -Not -Contain 'NextResult'
			$script:rowTest.State.Events[-2..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose'
			$script:rowTest.State.Events | Should -Not -Contain 'Connection.Dispose'
		}
	}

	It 'selects the first result with columns even if empty (Leading=<Leading>, Empty=<Empty>)' -ForEach @(
		@{ Leading = $false; Empty = $true }
		@{ Leading = $true; Empty = $true }
		@{ Leading = $true; Empty = $false }
	) {
		InModuleScope $Owner -Parameters @{ Leading = $Leading; Empty = $Empty } {
			$selected = @{ Names = @('First'); Rows = @() }
			if (-not $Empty) {
				$selected.Rows = @(@{ Values = @(7) })
			}
			$results = @($selected, @{ Names = @('Later'); Rows = @(@{ Values = @(9) }) })
			if ($Leading) {
				$results = @(@{ Names = @(); Rows = @() }) + $results
			}
			$script:rowTest.State.Results = $results
			$rows = @(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:rowTest.Connection -Query 'controlled')
			$rows.Count | Should -Be ([int](-not $Empty))
			$script:rowTest.State.ResultIndex | Should -Be ([int]$Leading)
			if (-not $Empty) {
				$rows[0].First | Should -Be 7
			}
		}
	}

	It 'emits nothing when every result has no columns' {
		InModuleScope $Owner {
			$script:rowTest.State.Results = @(@{ Names = @(); Rows = @() }, @{ Names = @(); Rows = @() })
			@(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:rowTest.Connection -Query 'controlled') | Should -HaveCount 0
			$script:rowTest.State.ReadCount | Should -Be 0
		}
	}

	It 'preserves column order, accepted names, native values, SQL null and binary arrays of length <Length>' -ForEach @(@{ Length = 0 }, @{ Length = 1 }, @{ Length = 3 }) {
		InModuleScope $Owner -Parameters @{ Length = $Length } {
			$payload = [byte[]]::new($Length)
			$when = [datetime]'2026-11-20'
			$script:rowTest.State.Results = @(@{
				Names = @('Upper Name', 'Amount', 'When', 'Nothing', 'Payload')
				Rows = @(@{ Values = @([long]42, [decimal]1.25, $when, [DBNull]::Value, $payload) })
			})
			$rows = @(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:rowTest.Connection -Query 'controlled' -Parameters @{
				payload = (New-Fast1GenericSqlParam -Type VarBinary -Value $payload)
				id = (New-Fast1GenericSqlParam -Type BigInt -Value 42)
			})
			$rows | Should -HaveCount 1
			$rows[0].PSObject.Properties.Name -join ',' | Should -Be 'Upper Name,Amount,When,Nothing,Payload'
			$rows[0].'Upper Name' | Should -BeOfType ([long])
			$rows[0].Amount | Should -BeOfType ([decimal])
			$rows[0].When | Should -Be $when
			($null -eq $rows[0].Nothing) | Should -BeTrue
			[object]::ReferenceEquals($payload, $rows[0].Payload) | Should -BeTrue
			[object]::ReferenceEquals($payload, $script:rowTest.Command.Parameters['@payload'].Value) | Should -BeTrue
			$script:rowTest.Command.Parameters['@id'].SqlDbType | Should -Be 'BigInt'
		}
	}

	It 'rejects <Kind> names before Read even for empty results (Empty=<Empty>)' -ForEach @(
		foreach ($empty in @($false, $true)) {
			@{ Kind = 'blank'; Names = @(''); Empty = $empty }
			@{ Kind = 'whitespace'; Names = @('  '); Empty = $empty }
			@{ Kind = 'duplicate'; Names = @('Id', 'ID'); Empty = $empty }
		}
	) {
		InModuleScope $Owner -Parameters @{ Names = $Names; Empty = $Empty } {
			$rows = @(@{ Values = @(1, 2) })
			if ($Empty) {
				$rows = @()
			}
			$script:rowTest.State.Results = @(@{ Names = $Names; Rows = $rows })
			{ Invoke-Fast1GenericSqlQueryReader -SqlConn $script:rowTest.Connection -Query 'controlled' } | Should -Throw '*distinct SQL aliases*'
			$script:rowTest.State.ReadCount | Should -Be 0
			$script:rowTest.State.Events[-2..-1] -join ',' | Should -Be 'Reader.Dispose,Command.Dispose'
		}
	}
}

Describe 'Public typed SQL parameter factory' {
	It 'requires an explicit valid type and exposes only the agreed metadata' {
		$command = Get-Command New-Fast1GenericSqlParam -ErrorAction Stop
		$parameterAttributes = @($command.Parameters.Type.Attributes | Where-Object {
			$_ -is [System.Management.Automation.ParameterAttribute]
		})
		$parameterAttributes.Mandatory | Should -Contain $true
		$command.Parameters.Type.ParameterType | Should -Be ([System.Data.SqlDbType])
		$command.Parameters.Size.ParameterType | Should -Be ([int])
		$command.Parameters.Precision.ParameterType | Should -Be ([byte])
		$command.Parameters.Scale.ParameterType | Should -Be ([byte])
		{ New-Fast1GenericSqlParam -Type $null } | Should -Throw
		{ New-Fast1GenericSqlParam -Type 'invalid' } | Should -Throw
	}

	It 'fails omitted mandatory Type in a noninteractive public caller' {
		$modulePath = Join-Path $script:distributionRoot 'Fast1data.SqlServer.psd1'
		$escaped = $modulePath.Replace("'", "''")
		$output = @(& (Join-Path $PSHOME 'pwsh') -NoProfile -NonInteractive -Command "Import-Module '$escaped'; New-Fast1GenericSqlParam -ErrorAction Stop" 2>&1)
		$LASTEXITCODE | Should -Not -Be 0
		($output -join "`n") | Should -Match 'Type|NonInteractive'
	}

	It 'creates exactly one BigInt descriptor from <Type> without private class imports' -ForEach @(
		@{ Type = 'BigInt' }
		@{ Type = 0 }
	) {
		$result = @(New-Fast1GenericSqlParam -Type $Type -Value 42)
		$result | Should -HaveCount 1
		$result[0].GetType().Name | Should -Be 'GenericSqlParam'
		$result[0].Type | Should -Be ([System.Data.SqlDbType]::BigInt)
		$result[0].Value | Should -Be 42
	}

	It 'represents omitted and explicit null values with default metadata' {
		foreach ($descriptor in @((New-Fast1GenericSqlParam -Type NVarChar), (New-Fast1GenericSqlParam -Type NVarChar -Value $null))) {
			$descriptor.Value | Should -BeNullOrEmpty
			$descriptor.Size | Should -Be 0
			$descriptor.Precision | Should -Be 0
			$descriptor.Scale | Should -Be 0
		}
	}

	It 'retains native binary arrays of length <Length>' -ForEach @(@{ Length = 0 }, @{ Length = 1 }, @{ Length = 3 }) {
		$payload = [byte[]]::new($Length)
		$descriptor = New-Fast1GenericSqlParam -Type VarBinary -Value $payload
		[object]::ReferenceEquals($payload, $descriptor.Value) | Should -BeTrue
	}

	It 'accepts nonnegative Size and byte metadata boundaries and rejects values outside them' {
		foreach ($size in @(0, [int]::MaxValue)) {
			$descriptor = New-Fast1GenericSqlParam -Type Decimal -Size $size -Precision 255 -Scale 255
			$descriptor.Size | Should -Be $size
			$descriptor.Precision | Should -Be 255
			$descriptor.Scale | Should -Be 255
		}
		{ New-Fast1GenericSqlParam -Type Int -Size -1 } | Should -Throw
		{ New-Fast1GenericSqlParam -Type Decimal -Precision 256 } | Should -Throw
		{ New-Fast1GenericSqlParam -Type Decimal -Scale -1 } | Should -Throw
	}

	It 'allocates no SQL command while creating a descriptor' {
		Mock Get-GenericSqlCommand -ModuleName Fast1data.SqlServer { throw 'Factory allocated SQL' }
		New-Fast1GenericSqlParam -Type Int -Value 1 | Should -Not -BeNullOrEmpty
		Should -Invoke Get-GenericSqlCommand -ModuleName Fast1data.SqlServer -Times 0 -Exactly
	}

	It 'supports WhatIf without creating a descriptor and explicit Confirm false for normal creation' {
		@(New-Fast1GenericSqlParam -Type BigInt -Value 42 -WhatIf) | Should -HaveCount 0
		$descriptor = @(New-Fast1GenericSqlParam -Type BigInt -Value 42 -Confirm:$false)
		$descriptor | Should -HaveCount 1
		$descriptor[0].Value | Should -Be 42
	}
}
