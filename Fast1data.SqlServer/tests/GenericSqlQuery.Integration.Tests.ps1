BeforeAll {
	Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fast1data.SqlServer.psd1') -Force
}

Describe 'Public SQL query provider acceptance' -Tag Integration -Skip:([string]::IsNullOrWhiteSpace($env:FAST1_TEST_MIGRATION_SQL_CONN_STR)) {
	BeforeAll {
		$script:databaseCreated = $false
		$script:queryConnection = $null
		$script:adminConnection = $null
		$script:databaseName = 'fast1_query_test_' + [guid]::NewGuid().ToString('N')
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($env:FAST1_TEST_MIGRATION_SQL_CONN_STR)
		$builder['Initial Catalog'] = 'master'
		$builder.Pooling = $false
		$script:adminConnection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
		$script:adminConnection.Open()
		Invoke-Fast1GenericSqlQuery -SqlConn $script:adminConnection -Query "CREATE DATABASE [$script:databaseName];"
		$script:databaseCreated = $true
		$builder['Initial Catalog'] = $script:databaseName
		$script:queryConnection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
		$script:queryConnection.Open()
		Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'CREATE PROCEDURE dbo.echo @Id bigint, @Name nvarchar(32) AS SELECT @Id AS Id, @Name AS Name;'
	}
	AfterAll {
		try {
			if ($null -ne $script:queryConnection) {
				$script:queryConnection.Dispose()
			}
			if ($script:databaseCreated -and $script:databaseName -match '^fast1_query_test_[0-9a-f]{32}$') {
				Invoke-Fast1GenericSqlQuery -SqlConn $script:adminConnection -Query "ALTER DATABASE [$script:databaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$script:databaseName];"
			}
		}
		finally {
			if ($null -ne $script:adminConnection) {
				$script:adminConnection.Dispose()
			}
		}
	}

	It 'emits only the first tabular result after non-tabular statements' {
		$rows = @(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query 'SET NOCOUNT OFF; CREATE TABLE #leading (Id int); INSERT #leading VALUES (1); SELECT Id FROM #leading; SELECT 2 AS Later; DROP TABLE #leading;')
		$rows | Should -HaveCount 1
		$rows[0].PSObject.Properties.Name -join ',' | Should -Be 'Id'
		$rows[0].Id | Should -Be 1
		@(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query 'SELECT 1 AS Empty WHERE 1 = 0; SELECT 2 AS Later;') | Should -HaveCount 0
		@(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query 'SET NOCOUNT ON;') | Should -HaveCount 0
	}

	It 'validates aliases even when the tabular result is empty' {
		foreach ($query in @('SELECT 1 WHERE 1 = 0;', 'SELECT 1 AS Id, 2 AS ID WHERE 1 = 0;', 'SELECT 1 AS [ ] WHERE 1 = 0;')) {
			{ Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query $query } | Should -Throw '*distinct SQL aliases*'
		}
		$row = Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query 'SELECT 1 AS [Accepted Name];'
		$row.'Accepted Name' | Should -Be 1
	}

	It 'preserves provider numeric/date/null/binary types and typed input values' {
		foreach ($length in @(0, 1, 3)) {
			$payload = [byte[]]::new($length)
			$rows = @(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query @'
SELECT @Id AS Id, @Name AS Name, @Payload AS Payload,
CAST(1.25 AS decimal(8,2)) AS Amount, CAST('2026-11-20' AS datetime2) AS Recorded;
'@ -Parameters @{
				Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
				Name = New-Fast1GenericSqlParam -Type NVarChar -Size 32
				Payload = New-Fast1GenericSqlParam -Type VarBinary -Size 10 -Value $payload
			})
			$rows | Should -HaveCount 1
			$rows[0].PSObject.Properties.Name -join ',' | Should -Be 'Id,Name,Payload,Amount,Recorded'
			$rows[0].Id | Should -BeOfType ([long])
			$rows[0].Id | Should -Be 42
			($null -eq $rows[0].Name) | Should -BeTrue
			$rows[0].Payload.GetType() | Should -Be ([byte[]])
			$rows[0].Payload.Length | Should -Be $length
			$rows[0].Amount | Should -BeOfType ([decimal])
			$rows[0].Recorded | Should -BeOfType ([datetime])
		}
	}

	It 'binds StoredProcedure inputs for rows and scalar execution' {
		$parameters = @{
			Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
			Name = New-Fast1GenericSqlParam -Type NVarChar -Size 32 -Value 'native'
		}
		$row = Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query dbo.echo -CommandType StoredProcedure -Parameters $parameters
		$row.Id | Should -Be 42
		$row.Name | Should -Be 'native'
		Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query dbo.echo -CommandType StoredProcedure -Parameters $parameters -Scalar | Should -Be 42
	}

	It 'preserves scalar empty/DBNull and silent non-query behavior' {
		Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'SELECT 42;' -Scalar | Should -Be 42
		($null -eq (Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'SELECT 1 WHERE 1 = 0;' -Scalar)) | Should -BeTrue
		Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'SELECT CAST(NULL AS int);' -Scalar | Should -Be ([DBNull]::Value)
		@(Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'CREATE TABLE #silent (Id int); INSERT #silent VALUES (1); DROP TABLE #silent;') | Should -HaveCount 0
	}

	It 'releases truncated readers and retains an open reusable caller connection after provider errors' {
		$rows = @(Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query 'SELECT Id FROM (VALUES (1), (2), (3)) AS source(Id);' | Select-Object -First 1)
		$rows | Should -HaveCount 1
		$rows[0].Id | Should -Be 1
		$script:queryConnection.State | Should -Be 'Open'
		Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'SELECT 1;' -Scalar | Should -Be 1
		{ Invoke-Fast1GenericSqlQueryReader -SqlConn $script:queryConnection -Query "THROW 51000, 'controlled provider failure', 1;" } | Should -Throw '*controlled provider failure*'
		Invoke-Fast1GenericSqlQuery -SqlConn $script:queryConnection -Query 'SELECT 2;' -Scalar | Should -Be 2
	}
}
