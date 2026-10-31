BeforeAll {
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force

	function Invoke-TestSql {
		param(
			[Parameter(Mandatory)]
			[string]$Query,

			[string]$ConnStr = $script:testConnectionString,

			[hashtable]$Parameters = @{}
		)

		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new(
			$ConnStr
		)
		$command = $null

		try {
			$connection.Open()
			$command = $connection.CreateCommand()
			$command.CommandText = $Query
			$command.CommandTimeout = 120

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

Describe 'Migration SQL integration' -Tag 'Integration' {
	BeforeAll {
		$script:testDatabaseCreated = $false
		# The SQL login must be allowed to create/drop a database.
		# Live test configuration: edit these values once for your test environment.
		$connectionString = @(
			'Data Source=pester-srv'
			'Initial Catalog=master'
			'User ID=pester'
			'Password=pester'
			'Encrypt=False'
			'TrustServerCertificate=True'
			'Application Name=Fast1data.SqlServer.Migration.Tests'
		) -join ';'
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
		$builder['Initial Catalog'] = 'master'
		$builder['Pooling'] = $false
		$script:masterConnectionString = $builder.ConnectionString
		$script:testDatabaseName = "fast1_migration_test_$([guid]::NewGuid().ToString('N'))"
		Invoke-TestSql -ConnStr $script:masterConnectionString `
			-Query "create database [$script:testDatabaseName];" | Out-Null
		$script:testDatabaseCreated = $true
		$builder['Initial Catalog'] = $script:testDatabaseName
		$script:testConnectionString = $builder.ConnectionString

		$sql = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'schema/migration/tables.sql') -Raw
		foreach ($batch in [regex]::Split($sql, '(?im)^\s*go\s*(?:--.*)?$')) {
			if (-not [string]::IsNullOrWhiteSpace($batch)) {
				Invoke-TestSql -Query $batch | Out-Null
			}
		}

		function Set-SqlFixtureScript {
			[CmdletBinding(SupportsShouldProcess)]
			param ([System.Collections.Specialized.OrderedDictionary]$Scripts)
			if ($PSCmdlet.ShouldProcess($script:phasePath, 'Configure SQL test scripts')) {
				foreach ($entry in $Scripts.GetEnumerator()) {
					$path = Join-Path $script:phasePath $entry.Key
					$null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
					Set-Content -LiteralPath $path -Value $entry.Value -NoNewline
				}
				$config = @{}
				$config[$script:phase] = @{ scripts = @($Scripts.Keys) }
				$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:basePath 'migration.json')
			}
		}

		function Get-SqlFixtureHistory {
			param ([string]$ConnStr = $script:testConnectionString)
			$json = Invoke-TestSql -ConnStr $ConnStr -Query @'
select script_name, [checksum], executed_at from dbo.fast1_migration_history
where phase = @phase order by script_name for json path;
'@ -Parameters @{ phase = $script:phase }
			$json | ConvertFrom-Json
		}

		function Get-SqlFixtureInsert {
			param ([int]$Id)
			@"
if not exists (select 1 from dbo.$script:tableName where id = $Id)
	insert dbo.$script:tableName(id) values($Id);
"@
		}

		$script:databaseCollation = Invoke-TestSql -Query "select convert(nvarchar(128), databasepropertyex(db_name(), 'Collation'))"
		Write-Information "Integration database collation: $script:databaseCollation" -InformationAction Continue
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

	AfterAll {
		if ($script:testDatabaseCreated) {
			Invoke-TestSql -ConnStr $script:masterConnectionString -Query @"
alter database [$script:testDatabaseName] set single_user with rollback immediate;
drop database [$script:testDatabaseName];
"@ | Out-Null
		}
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

	It 'previews real history including force without changing effects or any stored values' {
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$snapshotQuery = @"
select (select script_name, [checksum], executed_at from dbo.fast1_migration_history
where phase = @phase order by script_name for json path) + ':' +
convert(nvarchar(20), (select count(*) from dbo.$script:tableName));
"@
		$before = Invoke-TestSql -Query $snapshotQuery -Parameters @{ phase = $script:phase }
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
			-ForceScripts '001-IDEMPOTENT.SQL' -WhatIf -Verbose
		$after = Invoke-TestSql -Query $snapshotQuery -Parameters @{ phase = $script:phase }
		$after | Should -BeExactly $before
	}

	It 'executes ordered scripts, preserves skipped timestamps, and refreshes changed forced history without duplicates' {
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'z-first.sql' = $initial
			'nested/a-second.sql' = @"
if not exists (select 1 from dbo.$script:tableName where id = 1)
	throw 51000, 'execution order violated', 1;
if not exists (select 1 from dbo.fast1_migration_history where phase = N'$script:phase' and script_name = N'z-first.sql')
	throw 51000, 'recording order violated', 1;
$(Get-SqlFixtureInsert -Id 2)
"@
		})
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$before = @(Get-SqlFixtureHistory)
		$before.Count | Should -Be 2
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 2
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$skipped = @(Get-SqlFixtureHistory)
		($skipped | ConvertTo-Json -Compress) | Should -BeExactly ($before | ConvertTo-Json -Compress)
		# A deliberately old timestamp proves database time refreshed without relying on sleeps.
		Invoke-TestSql -Query "update dbo.fast1_migration_history set executed_at = '20000101' where phase = @phase; select 1" `
			-Parameters @{ phase = $script:phase } | Out-Null
		Add-Content -LiteralPath (Join-Path $script:phasePath 'nested/a-second.sql') -Value '-- changed forced rerun'
		$changed = Get-Content -LiteralPath (Join-Path $script:phasePath 'nested/a-second.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'z-first.sql' = $initial
			'nested/a-second.sql' = $changed
			'forced-new.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
			-ForceScripts 'NESTED\A-SECOND.SQL', 'FORCED-NEW.SQL' -Confirm:$false
		$after = @(Get-SqlFixtureHistory)
		$after.Count | Should -Be 3
		$second = $after | Where-Object script_name -EQ 'nested/a-second.sql'
		$second.script_name | Should -BeExactly 'nested/a-second.sql'
		$second.checksum | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:phasePath 'nested/a-second.sql')).Hash
		$second.checksum | Should -Not -Be ($before | Where-Object script_name -EQ 'nested/a-second.sql').checksum
		([datetime]$second.executed_at).Year | Should -BeGreaterThan 2000
		([datetime]($after | Where-Object script_name -EQ 'z-first.sql').executed_at).Year | Should -Be 2000
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 3
	}

	It 'updates legacy original keys (case-sensitive database required=<RequireCaseSensitive>)' -ForEach @(
		@{ RequireCaseSensitive = $false }
		@{ RequireCaseSensitive = $true }
	) {
		$connectionString = $script:testConnectionString
		$caseSensitiveDatabaseCreated = $false
		$caseSensitiveDatabaseName = "fast1_migration_cs_test_$([guid]::NewGuid().ToString('N'))"
		try {
			if ($RequireCaseSensitive) {
				Invoke-TestSql -ConnStr $script:masterConnectionString `
					-Query "create database [$caseSensitiveDatabaseName] collate Latin1_General_100_CS_AS;" | Out-Null
				$caseSensitiveDatabaseCreated = $true
				$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($script:masterConnectionString)
				$builder['Initial Catalog'] = $caseSensitiveDatabaseName
				$connectionString = $builder.ConnectionString

				$sql = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'schema/migration/tables.sql') -Raw
				foreach ($batch in [regex]::Split($sql, '(?im)^\s*go\s*(?:--.*)?$')) {
					if (-not [string]::IsNullOrWhiteSpace($batch)) {
						Invoke-TestSql -ConnStr $connectionString -Query $batch | Out-Null
					}
				}
				Invoke-TestSql -ConnStr $connectionString -Query "select case when N'a' = N'A' then 0 else 1 end;" |
					Should -Be 1
			}
			$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
			Set-SqlFixtureScript -Scripts ([ordered]@{ 'Nested/001-idempotent.sql' = $initial })
			Invoke-Fast1Migration -ConnStr $connectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
			Invoke-TestSql -ConnStr $connectionString -Query @'
update dbo.fast1_migration_history set script_name = @legacy, executed_at = '20000101'
where phase = @phase;
select 1;
'@ -Parameters @{ phase = $script:phase; legacy = 'NESTED\001-IDEMPOTENT.SQL' } | Out-Null
			$legacy = @(Get-SqlFixtureHistory -ConnStr $connectionString)[0]
			$legacy.script_name | Should -BeExactly 'NESTED\001-IDEMPOTENT.SQL'
			Add-Content -LiteralPath (Join-Path $script:phasePath 'Nested/001-idempotent.sql') -Value '-- new checksum'
			Invoke-Fast1Migration -ConnStr $connectionString -BasePath $script:basePath -Phase $script:phase `
				-ForceScripts 'nested/001-IDEMPOTENT.SQL' -Confirm:$false
			$after = @(Get-SqlFixtureHistory -ConnStr $connectionString)
			$after.Count | Should -Be 1
			$after[0].script_name | Should -BeExactly 'Nested/001-idempotent.sql'
			$after[0].checksum | Should -Not -Be $legacy.checksum
			$after[0].checksum | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:phasePath 'Nested/001-idempotent.sql')).Hash
			([datetime]$after[0].executed_at).Year | Should -BeGreaterThan 2000
			(Invoke-TestSql -ConnStr $connectionString -Query "select count(*) from dbo.$script:tableName") | Should -Be 1
		}
		finally {
			if ($caseSensitiveDatabaseCreated) {
				Invoke-TestSql -ConnStr $script:masterConnectionString -Query @"
alter database [$caseSensitiveDatabaseName] set single_user with rollback immediate;
drop database [$caseSensitiveDatabaseName];
"@ | Out-Null
			}
		}
	}

	It 'surfaces a later actual SQL execution error and retains only earlier recorded progress' {
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'first.sql' = $initial
			'fail.sql' = "throw 51000, 'fixture SQL execution failure', 1;"
			'last.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		} | Should -Throw
		$history = @(Get-SqlFixtureHistory)
		$history.Count | Should -Be 1
		$history[0].script_name | Should -BeExactly 'first.sql'
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 1") | Should -Be 1
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 3") | Should -Be 0
		# Repair only the fixture's failed SQL and retry: earlier success stays skipped.
		Set-Content -LiteralPath (Join-Path $script:phasePath 'fail.sql') -Value (Get-SqlFixtureInsert -Id 2)
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$retry = @(Get-SqlFixtureHistory)
		$retry.Count | Should -Be 3
		($retry | Where-Object script_name -EQ 'first.sql').executed_at | Should -Be $history[0].executed_at
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 3
	}

	It 'surfaces actual recording failure after SQL succeeds, stops later work, and retries idempotently' {
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'first.sql' = $initial
			'middle.sql' = "$(Get-SqlFixtureInsert -Id 2)`ndelete dbo.fast1_migration_history where phase = N'$script:phase' and script_name = N'middle.sql';"
			'last.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		Invoke-TestSql -Query @'
insert dbo.fast1_migration_history(phase, script_name, [checksum]) values(@phase, N'middle.sql', @checksum);
select 1;
'@ -Parameters @{ phase = $script:phase; checksum = ('0' * 64) } | Out-Null
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
				-ForceScripts 'middle.sql' -Confirm:$false
		} | Should -Throw '*script was not found in the migration history table*'
		$history = @(Get-SqlFixtureHistory)
		$history.Count | Should -Be 1
		$history[0].script_name | Should -BeExactly 'first.sql'
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 2") | Should -Be 1
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 3") | Should -Be 0
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$retry = @(Get-SqlFixtureHistory)
		$retry.Count | Should -Be 3
		($retry | Where-Object script_name -EQ 'first.sql').executed_at | Should -Be $history[0].executed_at
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 3
	}
}
