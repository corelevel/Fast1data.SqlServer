BeforeAll {
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force
	. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot $script:moduleRoot

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

Describe 'Migration SQL integration (select FAST1_TEST_SQL_CONNECTION_STRING to run)' -Tag 'Integration' -Skip:([string]::IsNullOrWhiteSpace($env:FAST1_TEST_SQL_CONNECTION_STRING)) {
	BeforeAll {
		$script:testDatabaseCreated = $false
		# The SQL login must be allowed to create/drop a database.
		$connectionString = $env:FAST1_TEST_SQL_CONNECTION_STRING
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

		function Invoke-DirectMigration {
			param ([string]$ConnStr = $script:testConnectionString, [string]$Script)
			& (Get-Module Fast1data.SqlServer) {
				param ($ConnectionString, $Path)
				Invoke-Migration -ConnStr $ConnectionString -Script $Path
			} $ConnStr $Script
		}
		function Invoke-BorrowedHistory {
			param ([Microsoft.Data.SqlClient.SqlCommand]$SqlCmd, [string]$Name = 'direct.sql', [bool]$Force = $false)
			& (Get-Module Fast1data.SqlServer) {
				param ($Command, $Name, $Phase, $Force)
				Set-Executed -SqlCmd $Command -ScriptName $Name -Phase $Phase -Checksum ('a' * 64) -ForceScript $Force
			} $SqlCmd $Name $script:phase $Force
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

	It 'executes exact original batches with temporary state, quoted text and batch-scoped definitions' {
		Invoke-TestSql -Query "create table dbo.$script:tableName(id int not null primary key);" | Out-Null
		$path = Join-Path $script:phasePath 'direct.sql'
		$source = @"
GO
CREATE TABLE #batch_state(id int);
INSERT #batch_state VALUES(1);
SELECT 'literal
GO
:r harmless';
/* multiline
GO 3
*/
gO
GO
CREATE PROCEDURE #batch_probe AS SELECT id FROM #batch_state;
GO
SET QUOTED_IDENTIFIER ON;
GO
EXEC #batch_probe;
INSERT dbo.$script:tableName("id") SELECT id FROM #batch_state;
GO
"@
		[System.IO.File]::WriteAllText($path, $source)
		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($script:testConnectionString)
		$command = $null
		try {
			$connection.Open()
			$command = $connection.CreateCommand()
			$command.CommandTimeout = 23
			Invoke-DirectMigration -Script $path
			[object]::ReferenceEquals($command.Connection, $connection) | Should -BeTrue
			$command.CommandTimeout | Should -Be 23
			$command.CommandText = "SELECT OBJECT_ID('tempdb..#batch_state');"
			$command.ExecuteScalar() | Should -Be ([DBNull]::Value)
			(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName;") | Should -Be 1
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
		}
	}

	It 'preflights a later <Failure> before effects or history or later scripts' -ForEach @(
		@{ Failure = 'syntax'; Tail = 'SELECT FROM;' }
		@{ Failure = 'directive'; Tail = ':r private-file.sql' }
		@{ Failure = 'substitution'; Tail = "SELECT '`$(Name)';" }
		@{ Failure = 'count 1'; Tail = 'GO 1' }
		@{ Failure = 'count 3'; Tail = 'GO 3' }
	) {
		Invoke-TestSql -Query "create table dbo.$script:tableName(id int not null primary key);" | Out-Null
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'fail.sql' = "INSERT dbo.$script:tableName VALUES(1);`nGO`n$Tail"
			'last.sql' = "INSERT dbo.$script:tableName VALUES(3);"
		})
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		} | Should -Throw '*fail.sql*line*column*'
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName;") | Should -Be 0
		@(Get-SqlFixtureHistory) | Should -HaveCount 0
	}

	It 'retains only earlier committed batches on runtime failure and completes an idempotent retry' {
		Invoke-TestSql -Query "create table dbo.$script:tableName(id int not null primary key);" | Out-Null
		$insert = Get-SqlFixtureInsert -Id 1
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'fail.sql' = "$insert`nGO`nTHROW 51000, 'controlled runtime failure', 1;`nGO`n$(Get-SqlFixtureInsert -Id 2)"
			'last.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		} | Should -Throw '*fail.sql*batch 2*'
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 1;") | Should -Be 1
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id in (2,3);") | Should -Be 0
		@(Get-SqlFixtureHistory) | Should -HaveCount 0
		[System.IO.File]::WriteAllText((Join-Path $script:phasePath 'fail.sql'), "$insert`nGO`n$(Get-SqlFixtureInsert -Id 2)")
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName;") | Should -Be 3
		@(Get-SqlFixtureHistory) | Should -HaveCount 2
	}

	It 'records each zero-batch file once and keeps history on its target after script USE' {
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'empty.sql' = ''
			'comments.sql' = "-- comment`nGO`n/* no statements */"
			'use.sql' = 'USE master;'
		})
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$history = @(Get-SqlFixtureHistory)
		$history | Should -HaveCount 3
		$history.script_name | Should -Be @('comments.sql', 'empty.sql', 'use.sql')
	}

	It 'preserves borrowed history transaction settings, reuse and rollback' {
		Invoke-TestSql -Query "create table dbo.$script:tableName(id int not null primary key);" | Out-Null
		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($script:testConnectionString)
		$command = $null
		$transaction = $null
		try {
			$connection.Open()
			$transaction = $connection.BeginTransaction()
			$command = $connection.CreateCommand()
			$command.Transaction = $transaction
			$command.CommandTimeout = 19
			$path = Join-Path $script:phasePath 'borrowed.sql'
			[System.IO.File]::WriteAllText($path, "SET XACT_ABORT OFF; CREATE TABLE #shared(id int);`nGO`nINSERT #shared VALUES(1); INSERT dbo.$script:tableName SELECT id FROM #shared;")
			Invoke-BorrowedHistory -SqlCmd $command
			$command.Parameters['@script_name'].SqlDbType | Should -Be 'NVarChar'
			$command.Parameters['@script_name'].Size | Should -Be 255
			$command.Parameters['@phase'].Size | Should -Be 32
			$command.Parameters['@checksum'].SqlDbType | Should -Be 'Char'
			$command.Parameters['@checksum'].Size | Should -Be 64
			$command.Parameters.Clear()
			$command.CommandText = "INSERT dbo.$script:tableName VALUES(1);"
			$null = $command.ExecuteNonQuery()
			$command.Parameters.Count | Should -Be 0
			$command.CommandText = "SELECT count(*) FROM dbo.$script:tableName;"
			$command.ExecuteScalar() | Should -Be 1
			{ Invoke-BorrowedHistory -SqlCmd $command -Name 'missing.sql' -Force $true } | Should -Throw '*history write failed*'
			[object]::ReferenceEquals($command.Transaction, $transaction) | Should -BeTrue
			[object]::ReferenceEquals($command.Connection, $connection) | Should -BeTrue
			$command.CommandTimeout | Should -Be 19
			$connection.State | Should -Be 'Open'
			$command.Parameters.Clear()
			$command.CommandText = 'SELECT 1;'
			$command.ExecuteScalar() | Should -Be 1
			$transaction.Rollback()
			(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName;") | Should -Be 0
			@(Get-SqlFixtureHistory) | Should -HaveCount 0
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			if ($null -ne $transaction) {
				$transaction.Dispose()
			}
			$connection.Dispose()
		}
	}

	It 'isolates pooled files from history while preserving within-file temporary state' {
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($script:testConnectionString)
		$builder.Pooling = $true
		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
		$command = $null
		try {
			$connection.Open()
			$command = $connection.CreateCommand()
			$command.CommandText = 'SELECT @@SPID;'
			$historySpid = [int]$command.ExecuteScalar()
			$command.CommandText = 'SELECT @@OPTIONS;'
			$historyOptions = [int]$command.ExecuteScalar()
			Invoke-TestSql -Query "CREATE TABLE dbo.$script:tableName(id int PRIMARY KEY, spid int);" | Out-Null
			$path = Join-Path $script:phasePath 'pooled.sql'
			[System.IO.File]::WriteAllText($path, @"
CREATE TABLE #file_state(spid int);
INSERT #file_state VALUES(@@SPID);
SET DATEFIRST 3;
SET ANSI_WARNINGS OFF;
GO
IF NOT EXISTS (SELECT 1 FROM #file_state WHERE spid = @@SPID) THROW 51000, 'Lost within-file state', 1;
INSERT dbo.$script:tableName VALUES(1, @@SPID);
USE master;
"@)
			Invoke-DirectMigration -ConnStr $builder.ConnectionString -Script $path
			$scriptSpid = Invoke-TestSql -Query "SELECT spid FROM dbo.$script:tableName WHERE id = 1;"
			$scriptSpid | Should -Not -Be $historySpid
			[object]::ReferenceEquals($command.Connection, $connection) | Should -BeTrue
			$connection.Database | Should -BeExactly $script:testDatabaseName
			$command.CommandText = "SELECT OBJECT_ID('tempdb..#file_state');"
			$command.ExecuteScalar() | Should -Be ([DBNull]::Value)
			$command.CommandText = 'SELECT @@OPTIONS;'
			$command.ExecuteScalar() | Should -Be $historyOptions
			Invoke-BorrowedHistory -SqlCmd $command -Name 'first.sql'
			[System.IO.File]::WriteAllText($path, @"
IF OBJECT_ID('tempdb..#file_state') IS NOT NULL THROW 51000, 'Leaked temporary state', 1;
IF DB_NAME() <> N'$script:testDatabaseName' THROW 51000, 'Wrong target', 1;
IF (@@OPTIONS & 8) = 0 THROW 51000, 'Leaked session options', 1;
IF @@TRANCOUNT <> 0 THROW 51000, 'Leaked transaction', 1;
INSERT dbo.$script:tableName VALUES(2, @@SPID);
"@)
			Invoke-DirectMigration -ConnStr $builder.ConnectionString -Script $path
			Invoke-BorrowedHistory -SqlCmd $command -Name 'second.sql'
			# Consecutive script SPIDs may match because pooling is allowed.
			(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName WHERE spid <> $historySpid;") | Should -Be 2
			@(Get-SqlFixtureHistory) | Should -HaveCount 2
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
			[Microsoft.Data.SqlClient.SqlConnection]::ClearPool($connection)
		}
	}

	It 'uses original configured/default catalog despite a changed history database (default=<DefaultCatalog>)' -ForEach @(
		@{ DefaultCatalog = $false }
		@{ DefaultCatalog = $true }
	) {
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($script:testConnectionString)
		if ($DefaultCatalog) {
			$null = $builder.Remove('Initial Catalog')
		}
		$originalString = $builder.ConnectionString
		$expectedCatalog = Invoke-TestSql -ConnStr $originalString -Query 'SELECT DB_NAME();'
		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($script:testConnectionString)
		$command = $null
		try {
			$connection.Open()
			$connection.ChangeDatabase('master')
			$command = $connection.CreateCommand()
			$command.CommandTimeout = 17
			$path = Join-Path $script:phasePath 'configured.sql'
			$catalogLiteral = $expectedCatalog.Replace("'", "''")
			[System.IO.File]::WriteAllText($path, "IF DB_NAME() <> N'$catalogLiteral' THROW 51000, 'Wrong target', 1;")
			Invoke-DirectMigration -ConnStr $originalString -Script $path
			$connection.Database | Should -BeExactly 'master'
			$command.CommandTimeout | Should -Be 17
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
		}
	}

	It 'authenticates from the original SQL-password string despite history redaction' {
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($script:testConnectionString)
		if ($builder.IntegratedSecurity -or [string]::IsNullOrEmpty($builder.UserID) -or [string]::IsNullOrEmpty($builder.Password)) {
			Set-ItResult -Skipped -Because 'Explicit SQL-password authentication was not configured.'
			return
		}
		$builder.PersistSecurityInfo = $false
		$originalString = $builder.ConnectionString
		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($originalString)
		$command = $null
		try {
			$connection.Open()
			$publicOptions = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($connection.ConnectionString)
			[string]::IsNullOrEmpty($publicOptions.Password) | Should -BeTrue
			$command = $connection.CreateCommand()
			$path = Join-Path $script:phasePath 'authentication.sql'
			[System.IO.File]::WriteAllText($path, "IF DB_NAME() <> N'$script:testDatabaseName' THROW 51000, 'Wrong authenticated target', 1;")
			Invoke-DirectMigration -ConnStr $originalString -Script $path
			Invoke-BorrowedHistory -SqlCmd $command
			@(Get-SqlFixtureHistory) | Should -HaveCount 1
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
		}
	}
	It 'suppresses ambient enlistment without losing committed script or history work' {
		Invoke-TestSql -Query "CREATE TABLE dbo.$script:tableName(id int PRIMARY KEY);" | Out-Null
		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($script:testConnectionString)
		$command = $null
		$scope = $null
		try {
			# History is opened before the ambient scope, so this test cannot pass via rollback.
			$connection.Open()
			$command = $connection.CreateCommand()
			$scope = [System.Transactions.TransactionScope]::new()
			$ambient = [System.Transactions.Transaction]::Current
			$path = Join-Path $script:phasePath 'ambient.sql'
			[System.IO.File]::WriteAllText($path, "INSERT dbo.$script:tableName VALUES(1);")
			Invoke-DirectMigration -Script $path
			[object]::ReferenceEquals([System.Transactions.Transaction]::Current, $ambient) | Should -BeTrue
			Invoke-BorrowedHistory -SqlCmd $command
			# Intentionally do not Complete: script/history must both survive ambient rollback.
		}
		finally {
			if ($null -ne $scope) {
				$scope.Dispose()
			}
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
		}
		(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName;") | Should -Be 1
		@(Get-SqlFixtureHistory) | Should -HaveCount 1
	}

	It 'requires balanced explicit transactions and permits an idempotent retry (ending=<Ending>)' -ForEach @(
		@{ Ending = 'COMMIT' }
		@{ Ending = 'ROLLBACK' }
		@{ Ending = 'unfinished' }
	) {
		Invoke-TestSql -Query "CREATE TABLE dbo.$script:tableName(id int PRIMARY KEY);" | Out-Null
		$endingSql = "$Ending;"
		if ($Ending -eq 'unfinished') {
			$endingSql = ''
		}
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'first.sql' = "BEGIN TRANSACTION; INSERT dbo.$script:tableName VALUES(1); $endingSql"
			'next.sql' = (Get-SqlFixtureInsert -Id 2)
		})
		if ($Ending -eq 'unfinished') {
			{ Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false } |
				Should -Throw '*transaction completion*'
			(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName;") | Should -Be 0
			@(Get-SqlFixtureHistory) | Should -HaveCount 0
			[System.IO.File]::WriteAllText((Join-Path $script:phasePath 'first.sql'), (Get-SqlFixtureInsert -Id 1))
		}
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$expectedRows = 2
		if ($Ending -eq 'ROLLBACK') {
			$expectedRows = 1
		}
		(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName;") | Should -Be $expectedRows
		@(Get-SqlFixtureHistory) | Should -HaveCount 2
	}

	It 'prevents history and later files when completion or owned cleanup fails at <Stage>' -ForEach @(
		@{ Stage = 'transaction check' }
		@{ Stage = 'command disposal' }
		@{ Stage = 'connection disposal' }
		@{ Stage = 'scope disposal' }
		@{ Stage = 'combined' }
	) {
		Invoke-TestSql -Query "CREATE TABLE dbo.$script:tableName(id int PRIMARY KEY);" | Out-Null
		$first = Get-SqlFixtureInsert -Id 1
		if ($Stage -eq 'combined') {
			$first += "`nGO`nTHROW 51000, 'controlled runtime failure', 1;"
		}
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'first.sql' = $first
			'next.sql' = (Get-SqlFixtureInsert -Id 2)
		})
		InModuleScope Fast1data.SqlServer -Parameters @{
			Stage = $Stage; ConnectionString = $script:testConnectionString; Base = $script:basePath; Phase = $script:phase
		} {
			$script:liveFailureStage = $Stage
			$script:liveConnectionFactory = (Get-Command Get-MigrationScriptConnection).ScriptBlock
			$script:liveCleanupEvents = [System.Collections.Generic.List[string]]::new()
			Mock Get-MigrationScriptConnection {
				$connection = & $script:liveConnectionFactory -ConnStr $ConnStr
				$connection | Add-Member -NotePropertyName CleanupEvents -NotePropertyValue $script:liveCleanupEvents
				$connection | Add-Member -NotePropertyName FailCleanup -NotePropertyValue ($script:liveFailureStage -in @('connection disposal', 'combined'))
				$connection | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.CleanupEvents.Add('connection')
					$this.psbase.Dispose()
					if ($this.FailCleanup) {
						throw 'controlled connection disposal failure'
					}
				}
				$connection
			}
			Mock Get-MigrationSuppressionScope {
				$scope = [pscustomobject]@{
					Actual = [System.Transactions.TransactionScope]::new([System.Transactions.TransactionScopeOption]::Suppress)
					Events = $script:liveCleanupEvents
					FailCleanup = ($script:liveFailureStage -in @('scope disposal', 'combined'))
				}
				$scope | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
					$this.Events.Add('scope')
					$this.Actual.Dispose()
					if ($this.FailCleanup) {
						throw 'controlled suppression disposal failure'
					}
				}
				$scope
			}
			Mock Get-MigrationScriptCommand {
				$command = $Connection.CreateCommand()
				$command | Add-Member -NotePropertyName CleanupEvents -NotePropertyValue $script:liveCleanupEvents
				$command | Add-Member -NotePropertyName FailCleanup -NotePropertyValue ($script:liveFailureStage -in @('command disposal', 'combined'))
				$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.CleanupEvents.Add('command')
					$this.psbase.Dispose()
					if ($this.FailCleanup) {
						throw 'controlled command disposal failure'
					}
				}
				if ($script:liveFailureStage -eq 'transaction check') {
					$command | Add-Member -MemberType ScriptMethod -Name ExecuteScalar -Force -Value { throw 'controlled completion check failure' }
				}
				$command
			}
			$caught = $null
			try {
				Invoke-Fast1Migration -ConnStr $ConnectionString -BasePath $Base -Phase $Phase -Confirm:$false
			}
			catch {
				$caught = $_
			}
			$caught | Should -Not -BeNullOrEmpty
			$script:liveCleanupEvents.ToArray() | Should -Be @('command', 'connection', 'scope')
			if ($Stage -eq 'combined') {
				$caught.Exception.Message | Should -Match 'batch 2'
				@(Get-GenericSqlCleanupFailure -ErrorRecord $caught) | Should -HaveCount 3
			}
			# Pester keeps these wrappers for this test; allow the following retry.
			$script:liveFailureStage = 'none'
		}
		(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName WHERE id = 1;") | Should -Be 1
		(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName WHERE id = 2;") | Should -Be 0
		@(Get-SqlFixtureHistory) | Should -HaveCount 0
		[System.IO.File]::WriteAllText((Join-Path $script:phasePath 'first.sql'), (Get-SqlFixtureInsert -Id 1))
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName;") | Should -Be 2
		@(Get-SqlFixtureHistory) | Should -HaveCount 2
	}

	It 'does not advance forced history for an unfinished transaction' {
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$before = @(Get-SqlFixtureHistory) | ConvertTo-Json -Compress
		[System.IO.File]::WriteAllText((Join-Path $script:phasePath '001-idempotent.sql'), "BEGIN TRANSACTION; DELETE dbo.$script:tableName;")
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -ForceScripts '001-idempotent.sql' -Confirm:$false
		} | Should -Throw '*transaction completion*'
		(@(Get-SqlFixtureHistory) | ConvertTo-Json -Compress) | Should -BeExactly $before
		(Invoke-TestSql -Query "SELECT COUNT(*) FROM dbo.$script:tableName;") | Should -Be 1
	}

	It 'leaves prior history and timestamp unchanged after a failed forced rerun' {
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$before = @(Get-SqlFixtureHistory) | ConvertTo-Json -Compress
		[System.IO.File]::WriteAllText((Join-Path $script:phasePath '001-idempotent.sql'), "THROW 51000, 'forced failure', 1;")
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -ForceScripts '001-idempotent.sql' -Confirm:$false
		} | Should -Throw '*batch 1*'
		(@(Get-SqlFixtureHistory) | ConvertTo-Json -Compress) | Should -BeExactly $before
	}

	It 'releases real public resources after <Outcome> and preserves history timeout' -ForEach @(
		@{ Outcome = 'success'; Source = 'SELECT 1;'; ExpectedFailure = $false }
		@{ Outcome = 'parse failure'; Source = 'SELECT FROM;'; ExpectedFailure = $true }
		@{ Outcome = 'runtime failure'; Source = "THROW 51000, 'controlled failure', 1;"; ExpectedFailure = $true }
	) {
		Set-SqlFixtureScript -Scripts ([ordered]@{ 'owner.sql' = $Source })
		InModuleScope Fast1data.SqlServer -Parameters @{
			ConnectionString = $script:testConnectionString
			Base = $script:basePath
			Phase = $script:phase
			ExpectedFailure = $ExpectedFailure
		} {
			$script:realOwnerTrace = [System.Collections.Generic.List[string]]::new()
			$script:realMigration = (Get-Command Invoke-Migration).ScriptBlock
			$script:realHistory = (Get-Command Set-Executed).ScriptBlock
			Mock Get-MigrationConnection {
				$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($ConnectionString)
				$connection | Add-Member -NotePropertyName Events -NotePropertyValue $script:realOwnerTrace
				$connection | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Events.Add('dispose connection')
					$this.psbase.Dispose()
				}
				$script:realOwnerConnection = $connection
				$connection
			}
			Mock Get-GenericSqlCommand {
				$command = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn)
				$command.CommandTimeout = 27
				$command | Add-Member -NotePropertyName Events -NotePropertyValue $script:realOwnerTrace
				$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Events.Add('dispose command')
					$this.psbase.Dispose()
				}
				$command
			}
			Mock Invoke-Migration {
				$script:realOwnerTrace.Add("script")
				& $script:realMigration -ConnStr $ConnStr -Script $Script
			}
			Mock Set-Executed {
				$script:realOwnerTrace.Add("history timeout $($SqlCmd.CommandTimeout)")
				& $script:realHistory -SqlCmd $SqlCmd -ScriptName $ScriptName -Phase $Phase -Checksum $Checksum -ForceScript $ForceScript -HistoryScriptName $HistoryScriptName
			}
			$invoke = {
				Invoke-Fast1Migration -ConnStr $ConnectionString -BasePath $Base -Phase $Phase -Confirm:$false
			}
			if ($ExpectedFailure) {
				$invoke | Should -Throw
				$script:realOwnerTrace.ToArray() | Should -Be @('script', 'dispose command', 'dispose connection')
			}
			else {
				& $invoke
				$script:realOwnerTrace.ToArray() | Should -Be @('script', 'history timeout 27', 'dispose command', 'dispose connection')
			}
			$script:realOwnerConnection.State | Should -Be 'Closed'
		}
		$expectedCount = 1
		if ($ExpectedFailure) {
			$expectedCount = 0
		}
		@(Get-SqlFixtureHistory) | Should -HaveCount $expectedCount
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
		} | Should -Throw '*history write failed*'
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
