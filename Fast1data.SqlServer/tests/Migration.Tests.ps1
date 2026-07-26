BeforeAll {
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force

	$script:testConnectionString = $env:FAST1_SQLSERVER_TEST_CONNECTION_STRING
	if ([string]::IsNullOrWhiteSpace($script:testConnectionString)) {
		$script:testConnectionString = @(
			'Data Source=(local)'
			'Initial Catalog=pester'
			'User ID=pester'
			'Password=pester'
			'Encrypt=False'
			'TrustServerCertificate=True'
			'Application Name=Fast1data.SqlServer.Tests'
		) -join ';'
	}

	function Invoke-TestSql {
		param(
			[Parameter(Mandatory)]
			[string]$Query,

			[hashtable]$Parameters = @{}
		)

		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new(
			$script:testConnectionString
		)
		$command = $null

		try {
			$connection.Open()
			$command = $connection.CreateCommand()
			$command.CommandText = $Query

			foreach ($entry in $Parameters.GetEnumerator()) {
				$parameter = $command.Parameters.AddWithValue(
					"@$($entry.Key)",
					$entry.Value
				)
				$null = $parameter
			}

			$command.ExecuteScalar()
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
		}
	}
}

Describe 'Migration configuration' {
	It 'selects a phase exactly and normalizes path separators' {
		$configPath = Join-Path $TestDrive 'migration.json'
		@'
{
	"phase01": {
		"scripts": [
			"First.sql",
			"Nested\\Second.sql"
		]
	},
	"phase02": {
		"scripts": [
			"Other.sql"
		]
	}
}
'@ | Set-Content -LiteralPath $configPath

		$result = InModuleScope 'Fast1data.SqlServer' -Parameters @{
			ConfigPath = $configPath
		} {
			Get-Migration -ConfigFile $ConfigPath -Phase 'phase01'
		}

		$result | Should -Be @(
			'First.sql'
			'Nested/Second.sql'
		)
	}

	It 'rejects a phase that does not exist' {
		$configPath = Join-Path $TestDrive 'missing-phase.json'
		'{"phase01":{"scripts":[]}}' |
			Set-Content -LiteralPath $configPath

		{
			InModuleScope 'Fast1data.SqlServer' -Parameters @{
				ConfigPath = $configPath
			} {
				Get-Migration -ConfigFile $ConfigPath -Phase 'phase99'
			}
		} | Should -Throw '*Migration phase not found*'
	}
}

Describe 'Migration validation' {
	It 'rejects scripts outside the selected phase directory' {
		$basePath = Join-Path $TestDrive 'traversal'
		$phasePath = Join-Path $basePath 'phase01'
		$null = New-Item -Path $phasePath -ItemType Directory -Force
		$null = New-Item -Path (Join-Path $basePath 'outside.sql') -ItemType File
		'{"phase01":{"scripts":["../outside.sql"]}}' |
			Set-Content -LiteralPath (Join-Path $basePath 'migration.json')

		InModuleScope 'Fast1data.SqlServer' -Parameters @{
			BasePath = $basePath
		} {
			Mock Get-Executed { @() }

			{
				Invoke-Fast1Migration `
					-ConnStr 'Data Source=(local);Initial Catalog=pester' `
					-BasePath $BasePath `
					-Phase 'phase01' `
					-WhatIf `
					-ErrorAction SilentlyContinue
			} | Should -Throw '*outside the phase directory*'
		}
	}

	It 'rejects scripts that are both ignored and forced' {
		$basePath = Join-Path $TestDrive 'intersection'
		$phasePath = Join-Path $basePath 'phase01'
		$null = New-Item -Path $phasePath -ItemType Directory -Force
		$null = New-Item -Path (Join-Path $phasePath 'Script.sql') -ItemType File
		'{"phase01":{"scripts":["Script.sql"]}}' |
			Set-Content -LiteralPath (Join-Path $basePath 'migration.json')

		InModuleScope 'Fast1data.SqlServer' -Parameters @{
			BasePath = $basePath
		} {
			Mock Get-Executed { @() }

			{
				Invoke-Fast1Migration `
					-ConnStr 'Data Source=(local);Initial Catalog=pester' `
					-BasePath $BasePath `
					-Phase 'phase01' `
					-IgnoreScripts 'script.sql' `
					-ForceScripts 'SCRIPT.SQL' `
					-WhatIf `
					-ErrorAction SilentlyContinue
			} | Should -Throw '*both ignored and forced*'
		}
	}
}

Describe 'Migration SQL integration' -Tag 'Integration' {
	BeforeAll {
		$schemaPath = Join-Path $script:moduleRoot 'schema\migration\tables.sql'
		Invoke-Sqlcmd `
			-ConnectionString $script:testConnectionString `
			-InputFile $schemaPath `
			-AbortOnError `
			-ErrorAction Stop |
			Out-Null
	}

	BeforeEach {
		$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
		$script:phase = "p_$suffix"
		$script:tableName = "migration_test_$suffix"
		$script:basePath = Join-Path $TestDrive $script:phase
		$script:phasePath = Join-Path $script:basePath $script:phase
		$null = New-Item -Path $script:phasePath -ItemType Directory -Force

		@"
{
	"$script:phase": {
		"scripts": [
			"001-idempotent.sql"
		]
	}
}
"@ | Set-Content -LiteralPath (Join-Path $script:basePath 'migration.json')

		@"
if object_id(N'dbo.$script:tableName', N'U') is null
begin
	create table dbo.$script:tableName
	(
		id int not null constraint PK_$script:tableName primary key
	)
end

if not exists (select 1 from dbo.$script:tableName where id = 1)
begin
	insert dbo.$script:tableName(id) values(1)
end
"@ | Set-Content -LiteralPath (
			Join-Path $script:phasePath '001-idempotent.sql'
		)
	}

	AfterEach {
		Invoke-TestSql `
			-Query @"
delete dbo.fast1_migration_history where phase = @phase;
if object_id(N'dbo.$script:tableName', N'U') is not null
	drop table dbo.$script:tableName;
select 1;
"@ `
			-Parameters @{ phase = $script:phase } |
			Out-Null
	}

	It 'executes, records, skips, and safely forces an idempotent migration' {
		Invoke-Fast1Migration `
			-ConnStr $script:testConnectionString `
			-BasePath $script:basePath `
			-Phase $script:phase

		$rowCount = Invoke-TestSql `
			-Query "select count(*) from dbo.$script:tableName"
		$historyCount = Invoke-TestSql `
			-Query 'select count(*) from dbo.fast1_migration_history where phase = @phase' `
			-Parameters @{ phase = $script:phase }

		$rowCount | Should -Be 1
		$historyCount | Should -Be 1

		Invoke-Fast1Migration `
			-ConnStr $script:testConnectionString `
			-BasePath $script:basePath `
			-Phase $script:phase

		Invoke-Fast1Migration `
			-ConnStr $script:testConnectionString `
			-BasePath $script:basePath `
			-Phase $script:phase `
			-ForceScripts '001-IDEMPOTENT.SQL'

		$rowCount = Invoke-TestSql `
			-Query "select count(*) from dbo.$script:tableName"
		$historyCount = Invoke-TestSql `
			-Query 'select count(*) from dbo.fast1_migration_history where phase = @phase' `
			-Parameters @{ phase = $script:phase }

		$rowCount | Should -Be 1
		$historyCount | Should -Be 1
	}
}
