# Supply closed, immutable audit files. Expected results are read directly from SQL Server.
# The SQL login must be allowed to create/drop a database and read audit files.
# The current Windows user and the SQL Server service must both be able to read Folder.
# Use a UNC path for a remote server; a local path must refer to the same files on both hosts.
Describe 'Live audit import from Windows' -Tag 'Windows', 'Integration' -Skip:(-not $IsWindows) {
	BeforeAll {
		$script:testDatabaseCreated = $false
		# Live test configuration: edit these values once for your test environment.
		$connectionString = @(
			'Data Source=pester-srv'
			'Initial Catalog=master'
			'User ID=pester'
			'Password=pester'
			'Encrypt=False'
			'TrustServerCertificate=True'
			'Application Name=Fast1data.SqlServer.Audit.Tests'
		) -join ';'
		$script:folder = '\\pester-srv\audit\void'

		# Windows discovery uses the current identity, independently of the SQL login.
		if (-not (Test-Path -LiteralPath $script:folder -PathType Container -ErrorAction Stop)) {
			throw "Audit folder is missing or inaccessible to the current Windows user: $script:folder"
		}
		$script:moduleRoot = Split-Path -Parent $PSScriptRoot
		Import-Module (Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1') -Force

		function Invoke-AuditTestSql {
			param (
				[Parameter(Mandatory)]
				[string]$Query,
				[string]$ConnStr = $script:testConnectionString,
				[hashtable]$Parameters = @{},
				[switch]$Scalar
			)
			$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($ConnStr)
			$command = $null
			try {
				$connection.Open()
				$command = $connection.CreateCommand()
				$command.CommandText = $Query
				$command.CommandTimeout = 120
				foreach ($entry in $Parameters.GetEnumerator()) {
					$null = $command.Parameters.AddWithValue("@$($entry.Key)", $entry.Value)
				}
				if ($Scalar) {
					return $command.ExecuteScalar()
				}
				$null = $command.ExecuteNonQuery()
			}
			finally {
				if ($null -ne $command) {
					$command.Dispose()
				}
				$connection.Dispose()
			}
		}

		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
		$builder['Initial Catalog'] = 'master'
		$builder['Pooling'] = $false
		$script:masterConnectionString = $builder.ConnectionString
		# Establish expectations independently of Invoke-Fast1Audit and its procedures.
		$sourceFiles = @(Invoke-AuditTestSql -ConnStr $script:masterConnectionString -Scalar `
			-Parameters @{ file_pattern = "$($script:folder.TrimEnd('\'))\*.sqlaudit" } -Query @'
select (
	select file_name, count_big(*) as record_count
	from sys.fn_get_audit_file(@file_pattern, default, default)
	group by file_name
	for json path
);
'@ | ConvertFrom-Json)
		$script:expectedRowCount = [long]0
		$script:expectedAuditGuids = @(
			foreach ($sourceFile in $sourceFiles) {
				$fileName = ($sourceFile.file_name -split '[\\/]')[-1]
				if ($fileName -notmatch '^.+_(?<AuditGuid>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_\d+_\d+\.sqlaudit$') {
					throw "The fixture contains an unexpected audit filename: $fileName"
				}
				$script:expectedRowCount += [long]$sourceFile.record_count
				[guid]$Matches.AuditGuid
			}
		) | Sort-Object -Unique
		if ($script:expectedRowCount -le 0) {
			throw "No audit records found in $script:folder. Supply closed, nonempty .sqlaudit files."
		}
		Write-Information "Source fixture: $script:expectedRowCount records in $($sourceFiles.Count) file(s)." -InformationAction Continue

		$script:testDatabaseName = "fast1_audit_test_$([guid]::NewGuid().ToString('N'))"
		Invoke-AuditTestSql -ConnStr $script:masterConnectionString `
			-Query "create database [$script:testDatabaseName];"
		$script:testDatabaseCreated = $true
		$builder['Initial Catalog'] = $script:testDatabaseName
		$script:testConnectionString = $builder.ConnectionString
		$script:importArguments = @{
			ConnStr = $script:testConnectionString
			Folder = $script:folder
			ErrorAction = 'Stop'
		}
		foreach ($schemaFile in @('tables.sql', 'sprocs.sql')) {
			$sql = Get-Content -LiteralPath (Join-Path $script:moduleRoot "schema/audit/$schemaFile") -Raw
			foreach ($batch in [regex]::Split($sql, '(?im)^\s*go\s*(?:--.*)?$')) {
				if (-not [string]::IsNullOrWhiteSpace($batch)) {
					Invoke-AuditTestSql -Query $batch
				}
			}
		}
	}

	BeforeEach {
		# Only the uniquely named database created by this suite is reset.
		Invoke-AuditTestSql -Query @'
delete from dbo.fast1_audit;
delete from dbo.import_state;
delete from dbo.ignored_action_id_class_type;
'@
	}

	AfterAll {
		if ($script:testDatabaseCreated) {
			Invoke-AuditTestSql -ConnStr $script:masterConnectionString -Query @"
alter database [$script:testDatabaseName] set single_user with rollback immediate;
drop database [$script:testDatabaseName];
"@
		}
	}

	It 'imports the expected records and audit GUIDs from real audit files using Windows discovery' {
		$messages = @(Invoke-Fast1Audit @script:importArguments -Verbose 4>&1)

		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.fast1_audit;' -Scalar |
			Should -Be $script:expectedRowCount
		$actualGuids = Invoke-AuditTestSql -Query @'
select distinct audit_guid from dbo.fast1_audit order by audit_guid for json path;
'@ -Scalar | ConvertFrom-Json
		@($actualGuids.audit_guid | Sort-Object) |
			Should -Be @($script:expectedAuditGuids | ForEach-Object { $_.ToString() } | Sort-Object -Unique)
		$checkpointGuids = Invoke-AuditTestSql -Query @'
select distinct audit_guid from dbo.import_state order by audit_guid for json path;
'@ -Scalar | ConvertFrom-Json
		@($checkpointGuids.audit_guid | Sort-Object) |
			Should -Be @($script:expectedAuditGuids | ForEach-Object { $_.ToString() } | Sort-Object -Unique)
		($messages.Message -join "`n") | Should -BeLike "*$script:expectedRowCount audit records imported*"
	}

	It 'resumes from saved checkpoints without duplicating records on a second import' {
		Invoke-Fast1Audit @script:importArguments
		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.fast1_audit;' -Scalar |
			Should -Be $script:expectedRowCount
		$checkpointQuery = @'
select file_name, audit_file_offset, audit_guid, modified_at
from dbo.import_state order by file_name for json path;
'@
		$before = Invoke-AuditTestSql -Query $checkpointQuery -Scalar
		$before | Should -Not -Be '[]'

		$messages = @(Invoke-Fast1Audit @script:importArguments -Verbose 4>&1)

		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.fast1_audit;' -Scalar |
			Should -Be $script:expectedRowCount
		Invoke-AuditTestSql -Query $checkpointQuery -Scalar | Should -BeExactly $before
		($messages.Message -join "`n") | Should -Match '\[Verbose\] 0 audit records imported'
		($messages.Message -join "`n") | Should -Match '\[Verbose\] 0 audit records processed'
	}

	It 'advances checkpoints for ignored records and does not reread them on the next import' {
		Invoke-Fast1Audit @script:importArguments
		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.fast1_audit;' -Scalar |
			Should -Be $script:expectedRowCount
		# Ignore every action/class in this fixture, then import it afresh.
		Invoke-AuditTestSql -Query @'
insert dbo.ignored_action_id_class_type(server_instance_name, action_id, class_type)
select distinct server_instance_name, action_id, class_type from dbo.fast1_audit;
delete from dbo.fast1_audit;
delete from dbo.import_state;
'@
		$messages = @(Invoke-Fast1Audit @script:importArguments -Verbose 4>&1)

		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.fast1_audit;' -Scalar | Should -Be 0
		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.import_state;' -Scalar | Should -BeGreaterThan 0
		($messages.Message -join "`n") | Should -BeLike "*$script:expectedRowCount audit records processed*"
		($messages.Message -join "`n") | Should -Match '\[Verbose\] 0 audit records imported'

		$repeatMessages = @(Invoke-Fast1Audit @script:importArguments -Verbose 4>&1)
		Invoke-AuditTestSql -Query 'select count_big(*) from dbo.fast1_audit;' -Scalar | Should -Be 0
		($repeatMessages.Message -join "`n") | Should -Match '\[Verbose\] 0 audit records processed'
		($repeatMessages.Message -join "`n") | Should -Match '\[Verbose\] 0 audit records imported'
	}
}
