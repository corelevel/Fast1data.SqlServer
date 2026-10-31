BeforeAll {
	$script:createdDatabases = [System.Collections.Generic.List[string]]::new()
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force

	# The SQL login must be allowed to create/drop databases.
	# Live test configuration: edit only the server and credentials.
	$connectionString = @(
		'Data Source=pester-srv'
		'User ID=pester'
		'Password=pester'
		'Encrypt=False'
		'TrustServerCertificate=True'
		'Application Name=Fast1data.SqlServer.Archiving.Tests'
		'Initial Catalog=master'
	) -join ';'
	$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($connectionString)
	$script:masterConnectionString = $builder.ConnectionString
	$script:serverName = $builder.DataSource
	$script:destinationServerName = $builder.DataSource

	$testRunId = [guid]::NewGuid().ToString('N')
	$script:configDatabase = "fast1_archiving_test_${testRunId}_config"
	$script:sourceDatabase = "fast1_archiving_test_${testRunId}_src"
	$script:destinationDatabase = "fast1_archiving_test_${testRunId}_dst"
	$builder['Initial Catalog'] = $script:configDatabase
	$script:configConnectionString = $builder.ConnectionString
	$builder['Initial Catalog'] = $script:sourceDatabase
	$script:sourceConnectionString = $builder.ConnectionString
	$builder['Initial Catalog'] = $script:destinationDatabase
	$script:destinationConnectionString = $builder.ConnectionString
	$null = $builder.Remove('Data Source')
	$null = $builder.Remove('Initial Catalog')
	$script:connectionOptions = $builder.ConnectionString
	$script:destinationConnectionOptions = $builder.ConnectionString

	function Invoke-ArchivingTestSql {
		param (
			[Parameter(Mandatory)]
			[string]$ConnectionString,

			[Parameter(Mandatory)]
			[string]$Query,

			[hashtable]$Parameters = @{},

			[switch]$Scalar
		)

		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new(
			$ConnectionString
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

	function Invoke-ArchivingTestSqlFile {
		param (
			[Parameter(Mandatory)]
			[string]$ConnectionString,

			[Parameter(Mandatory)]
			[string]$Path
		)

		$sql = Get-Content -LiteralPath $Path -Raw
		$batches = [regex]::Split(
			$sql,
			'(?im)^\s*go\s*(?:--.*)?$'
		)

		foreach ($batch in $batches) {
			if (-not [string]::IsNullOrWhiteSpace($batch)) {
				Invoke-ArchivingTestSql `
					-ConnectionString $ConnectionString `
					-Query $batch
			}
		}
	}

	function Invoke-ArchivingTestCheckpointFault {
		param ([string]$Condition)
		$script:checkpointTrigger = "TR_$($script:tableName)_checkpoint"
		$script:injections.Add(@{ ConnectionString = $script:configConnectionString; Query = "drop trigger if exists dbo.[$script:checkpointTrigger]" })
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query @"
create trigger dbo.[$script:checkpointTrigger] on dbo.ProcessState after update as
begin
	set nocount on;
	if exists (
		select 1 from inserted i join deleted d on d.ProcessStateId = i.ProcessStateId
		join dbo.SourceTable st on st.SourceTableId = i.SourceTableId
		where st.TableName = N'$script:tableName' and ($Condition)
	)
		throw 51001, 'Intentional checkpoint interruption', 1;
end;
"@
	}

	function Get-ArchivingTestState {
		$stateJson = Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query @'
select ps.*,
	case when object_id(N'dbo.' + quotename(st.SrcWorkingTableName), N'U') is null then 0 else 1 end WorkingSetExists
from dbo.ProcessState ps join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.Name = @group_name
order by ps.ProcessStateId desc for json path, include_null_values
'@ -Parameters @{ group_name = $script:groupName }
		if ([string]::IsNullOrEmpty($stateJson)) {
			return $null
		}
		@($stateJson | ConvertFrom-Json)[0]
	}

	function Save-ArchivingTestEvidence {
		param ([string]$Stage)
		$sourceKeys = Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select Id from dbo.[$script:tableName] order by Id for json path"
		$destinationKeys = Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "if object_id(N'dbo.$script:tableName', N'U') is null select N'[]'; else select Id from dbo.[$script:tableName] order by Id for json path"
		if ([string]::IsNullOrEmpty($sourceKeys)) {
			$sourceKeys = '[]'
		}
		if ([string]::IsNullOrEmpty($destinationKeys)) {
			$destinationKeys = '[]'
		}
		$workingKeys = Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query "if object_id(N'dbo.dbo_$($script:tableName)__src', N'U') is null select N'[]'; else select [$($script:tableName)__key] Position, Id, [$($script:tableName)__skip] Skipped from dbo.[dbo_$($script:tableName)__src] order by [$($script:tableName)__key] for json path"
		if ([string]::IsNullOrEmpty($workingKeys)) {
			$workingKeys = '[]'
		}
		$evidence = [ordered]@{ Fixture = $script:groupName; Stage = $Stage; SourceKeys = @($sourceKeys | ConvertFrom-Json); DestinationKeys = @($destinationKeys | ConvertFrom-Json); WorkingKeys = @($workingKeys | ConvertFrom-Json); State = Get-ArchivingTestState }
		Write-Verbose ($evidence | ConvertTo-Json -Depth 5 -Compress)
	}

	function Initialize-ArchivingTestForeignKey {
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query @'
update dbo.TableGroup set DisableFK = 1 where Name = @group_name;
insert dbo.ProcessState(SourceTableId, CompleteDate)
select st.SourceTableId, sysdatetime() from dbo.SourceTable st
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId where tg.Name = @group_name;
'@ -Parameters @{ group_name = $script:groupName }
		foreach ($child in @('a', 'b')) {
			Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query @"
create table dbo.[$($script:tableName)_child_$child] (
	Id int primary key, ParentId int not null,
	constraint [FK_$($script:tableName)_$child] foreign key (ParentId) references dbo.[$script:tableName](Id)
);
insert dbo.[$($script:tableName)_child_$child] values (1, 1);
"@
		}
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "alter table dbo.[$($script:tableName)_child_b] nocheck constraint [FK_$($script:tableName)_b]"
	}

	function Get-ArchivingTestForeignKey {
		$json = Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query @'
select name, is_disabled, is_not_trusted from sys.foreign_keys
where name in (@first, @second) order by name for json path
'@ -Parameters @{ first = "FK_$($script:tableName)_a"; second = "FK_$($script:tableName)_b" }
		Write-Information "Foreign keys $json" -InformationAction Continue
		$json | ConvertFrom-Json
	}

	$tablesPath = Join-Path $script:moduleRoot 'schema\archiving\tables.sql'
	$sprocsPath = Join-Path $script:moduleRoot 'schema\archiving\sprocs.sql'
	foreach ($databaseName in @($script:configDatabase, $script:sourceDatabase, $script:destinationDatabase)) {
		Invoke-ArchivingTestSql -ConnectionString $script:masterConnectionString -Query "create database [$databaseName];"
		$script:createdDatabases.Add($databaseName)
	}

	Invoke-ArchivingTestSqlFile `
		-ConnectionString $script:configConnectionString `
		-Path $tablesPath

	Invoke-ArchivingTestSqlFile `
		-ConnectionString $script:configConnectionString `
		-Path $sprocsPath
}

AfterAll {
	$databaseCleanupError = $null
	$databasesToDrop = $script:createdDatabases.ToArray()
	[array]::Reverse($databasesToDrop)
	foreach ($databaseName in $databasesToDrop) {
		try {
			Invoke-ArchivingTestSql -ConnectionString $script:masterConnectionString -Query @"
alter database [$databaseName] set single_user with rollback immediate;
drop database [$databaseName];
"@
		}
		catch {
			Write-Warning "Failed to drop test database [$databaseName]."
			if ($null -eq $databaseCleanupError) {
				$databaseCleanupError = $_
			}
		}
	}
	if ($null -ne $databaseCleanupError) {
		throw $databaseCleanupError
	}
}

Describe 'Fast1data.SqlServer archiving' {
	It 'exports Invoke-Fast1Archiving' {
		Get-Command Invoke-Fast1Archiving -Module Fast1data.SqlServer |
			Should -Not -BeNullOrEmpty
	}

	It 'rejects a table group that does not exist' {
		$missingGroup = "missing_$([guid]::NewGuid().ToString('N'))"

		{
			Invoke-Fast1Archiving `
				-ConnStr $script:configConnectionString `
				-GroupName $missingGroup `
				-ErrorAction SilentlyContinue
		} | Should -Throw '*table group*not found*'
	}
}

Describe 'Archiving SQL integration' -Tag 'Integration' {
	BeforeEach {
		$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
		$script:groupName = "pester_$suffix"
		$script:tableName = "archiving_test_$suffix"
		$script:injections = [System.Collections.Generic.List[object]]::new()

		Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query @"
create table dbo.$script:tableName
(
	Id int not null constraint PK_$script:tableName primary key,
	Value nvarchar(100) not null
);

insert dbo.$script:tableName(Id, Value)
values (1, N'one'), (2, N'two'), (3, N'three'), (4, N'four'), (5, N'five');
"@

		Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @"
insert dbo.TableGroup
(
	[Name],
	SrcServerName,
	SrcDatabaseName,
	SrcConnOptions,
	DstServerName,
	DstDatabaseName,
	DstConnOptions,
	DisableFK
)
values
(
	@group_name,
	@source_server,
	@source_database,
	@connection_options,
	@destination_server,
	@destination_database,
	@destination_options,
	0
);

declare @table_group_id int = scope_identity();

insert dbo.SourceTable
(
	TableGroupId,
	SchemaName,
	TableName,
	Active,
	DataCopyBatchSize,
	KeyCopyBatchSize,
	PurgeBatchSize,
	KeyQuery,
	Archive,
	Purge,
	PurgeOrder,
	DelayInterval,
	AlwaysRunCheck
)
values
(
	@table_group_id,
	N'dbo',
	@table_name,
	1,
	2,
	2,
	2,
	N'select Id from dbo.' + quotename(@table_name),
	1,
	1,
	1,
	'00:00:00',
	0
);
"@ `
			-Parameters @{
				group_name = $script:groupName
				table_name = $script:tableName
				connection_options = $script:connectionOptions
				destination_options = $script:destinationConnectionOptions
				source_server = $script:serverName
				source_database = $script:sourceDatabase
				destination_server = $script:destinationServerName
				destination_database = $script:destinationDatabase
			}
	}

	AfterEach {
		foreach ($injection in $script:injections) {
			Invoke-ArchivingTestSql -ConnectionString $injection.ConnectionString -Query $injection.Query
		}
		Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @"
declare @drop nvarchar(max);
select @drop = string_agg(cast(N'drop table if exists dbo.' + quotename(st.SrcWorkingTableName) + N'; drop table if exists dbo.' + quotename(st.DstWorkingTableName) + N';' as nvarchar(max)), N' ')
from dbo.SourceTable st
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name;
if @drop is not null exec sp_executesql @drop;

delete ps
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name;

delete st
from dbo.SourceTable st
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name;

delete dbo.TableGroup where [Name] = @group_name;
"@ `
			-Parameters @{ group_name = $script:groupName }

		foreach ($connectionString in @(
			$script:sourceConnectionString
			$script:destinationConnectionString
		)) {
			foreach ($child in @('a', 'b')) {
				Invoke-ArchivingTestSql -ConnectionString $connectionString -Query "drop table if exists dbo.[$($script:tableName)_child_$child]"
			}
			Invoke-ArchivingTestSql `
				-ConnectionString $connectionString `
				-Query @"
if object_id(N'dbo.$script:tableName', N'U') is not null
	drop table dbo.$script:tableName;
"@
		}
	}

	It 'retries a committed copy after its checkpoint fails with changed eligibility' {
		Invoke-ArchivingTestCheckpointFault -Condition 'i.LastArchivedKey > isnull(d.LastArchivedKey, 0)'
		Save-ArchivingTestEvidence -Stage 'before copy checkpoint fixture'
		{
			Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue
		} | Should -Throw '*Intentional checkpoint interruption*'
		$state = Get-ArchivingTestState
		$state.LastArchivedKey | Should -Be 0
		$state.WorkingSetExists | Should -Be 1
		$state.CompleteDate | Should -BeNullOrEmpty
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be 2
		Save-ArchivingTestEvidence -Stage 'copy committed; checkpoint rejected'
		# The retry query would exclude a committed destination key. Capture must
		# remain authoritative; neither changed eligibility nor a new key replaces it.
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "update dbo.[$script:tableName] set Value = N'excluded' where Id = 1; insert dbo.[$script:tableName] values (99, N'outside');"
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Query "update dbo.[$script:tableName] set Value = N'excluded' where Id = 1;"
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "update dbo.SourceTable set KeyQuery = N'select Id from dbo.[$script:tableName] where Value <> N''excluded''' where TableName = @table_name" -Parameters @{ table_name = $script:tableName }
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "drop trigger dbo.[$script:checkpointTrigger]"
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName] where Id = 99" | Should -Be 1
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName] where Id <> 99" | Should -Be 0
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be 5
		(Get-ArchivingTestState).RowsArchived | Should -Be 3
		Save-ArchivingTestEvidence -Stage 'copy retry completed; outside key retained'
	}

	It 'retries a committed delete after its checkpoint fails without inventing counts' {
		Invoke-ArchivingTestCheckpointFault -Condition 'i.LastPurgedKey > isnull(d.LastPurgedKey, 0)'
		Save-ArchivingTestEvidence -Stage 'before delete checkpoint fixture'
		{
			Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue
		} | Should -Throw '*Intentional checkpoint interruption*'
		$state = Get-ArchivingTestState
		$state.LastPurgedKey | Should -Be 0
		$state.RowsPurged | Should -Be 0
		$state.ArchiveCompleteDate | Should -Not -BeNullOrEmpty
		$state.PurgeCompleteDate | Should -BeNullOrEmpty
		$state.WorkingSetExists | Should -Be 1
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be 3
		Save-ArchivingTestEvidence -Stage 'delete committed; checkpoint rejected'
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "insert dbo.[$script:tableName] values (99, N'outside');"
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "drop trigger dbo.[$script:checkpointTrigger]"
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		(Get-ArchivingTestState).RowsPurged | Should -Be 3
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName] where Id = 99" | Should -Be 1
		Save-ArchivingTestEvidence -Stage 'delete retry completed; three recorded deletions'
	}

	It 'stops after a rejected <Transition> transition and retries persisted truth' -ForEach @(
		@{ Transition = 'maximum'; Condition = 'd.KeyMaxValue is null and i.KeyMaxValue is not null'; Copied = 0; Remaining = 5 }
		@{ Transition = 'capture'; Condition = 'd.KeyCopyDate is null and i.KeyCopyDate is not null'; Copied = 0; Remaining = 5 }
		@{ Transition = 'archive completion'; Condition = 'd.ArchiveCompleteDate is null and i.ArchiveCompleteDate is not null'; Copied = 5; Remaining = 5 }
		@{ Transition = 'purge completion'; Condition = 'd.PurgeCompleteDate is null and i.PurgeCompleteDate is not null'; Copied = 5; Remaining = 0 }
		@{ Transition = 'overall completion'; Condition = 'd.CompleteDate is null and i.CompleteDate is not null'; Copied = 5; Remaining = 0 }
	) {
		Invoke-ArchivingTestCheckpointFault -Condition $Condition
		{
			Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue
		} | Should -Throw '*Intentional checkpoint interruption*'
		$state = Get-ArchivingTestState
		$state.CompleteDate | Should -BeNullOrEmpty
		$state.WorkingSetExists | Should -Be 1
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be $Copied
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be $Remaining
		Save-ArchivingTestEvidence -Stage "$Transition rejected"
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "drop trigger dbo.[$script:checkpointTrigger]"
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		(Get-ArchivingTestState).CompleteDate | Should -Not -BeNullOrEmpty
		(Get-ArchivingTestState).WorkingSetExists | Should -Be 0
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be 5
		Save-ArchivingTestEvidence -Stage "$Transition retry completed"
	}

	It 'restores inbound source FKs after a <Fault> with unequal table/process IDs' -ForEach @(
		@{ Fault = 'delete' }
		@{ Fault = 'checkpoint' }
	) {
		Initialize-ArchivingTestForeignKey
		if ($Fault -eq 'checkpoint') {
			Invoke-ArchivingTestCheckpointFault -Condition 'i.LastPurgedKey > isnull(d.LastPurgedKey, 0)'
		}
		else {
			$trigger = "TR_$($script:tableName)_delete"
			$script:injections.Add(@{ ConnectionString = $script:sourceConnectionString; Query = "drop trigger if exists dbo.[$trigger]" })
			Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "create trigger dbo.[$trigger] on dbo.[$script:tableName] after delete as throw 51002, 'Intentional delete interruption', 1;"
		}
		{ Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue } | Should -Throw '*Intentional*interruption*'
		$state = Get-ArchivingTestState
		$state.SourceTableId | Should -Not -Be $state.ProcessStateId
		$state.PurgeCompleteDate | Should -BeNullOrEmpty
		$state.CompleteDate | Should -BeNullOrEmpty
		$state.WorkingSetExists | Should -Be 1
		$fks = @(Get-ArchivingTestForeignKey)
		$fks.Count | Should -Be 2
		@($fks | Where-Object is_disabled).Count | Should -Be 0
		@($fks | Where-Object is_not_trusted).Count | Should -Be 2
		Save-ArchivingTestEvidence -Stage "FK $Fault failure restored"
		foreach ($injection in $script:injections) {
			Invoke-ArchivingTestSql -ConnectionString $injection.ConnectionString -Query $injection.Query
		}
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		(Get-ArchivingTestState).CompleteDate | Should -Not -BeNullOrEmpty
		@(Get-ArchivingTestForeignKey | Where-Object is_disabled).Count | Should -Be 0
	}

	It 'attempts independent real FK restores after <Fault>, preserving primary errors' -ForEach @(
		@{ Fault = 'partial disable'; EarlierError = $false }
		@{ Fault = 'restore'; EarlierError = $false }
		@{ Fault = 'restore'; EarlierError = $true }
	) {
		Initialize-ArchivingTestForeignKey
		if ($EarlierError) {
			Invoke-ArchivingTestCheckpointFault -Condition 'i.LastPurgedKey > isnull(d.LastPurgedKey, 0)'
		}
		InModuleScope ArchivingModel -Parameters @{ Fault = $Fault } {
			$script:realConstraintAction = (Get-Command Invoke-ArchivingConstraintAction).ScriptBlock
			$script:constraintFault = $Fault
			$script:constraintAttempts = [System.Collections.Generic.List[string]]::new()
			Mock Invoke-ArchivingConstraintAction {
				param ($Connection, $Constraint, $Disable)
				$script:constraintAttempts.Add("$($Constraint.ConstraintName):$Disable")
				if ($script:constraintFault -eq 'restore' -and -not $Disable -and $Constraint.ConstraintName.EndsWith('_a')) {
					throw 'Intentional restore interruption'
				}
				& $script:realConstraintAction -Connection $Connection -Constraint $Constraint -Disable $Disable
				if ($script:constraintFault -eq 'partial disable' -and $Disable -and $Constraint.ConstraintName.EndsWith('_a')) {
					throw 'Intentional disable interruption'
				}
			}
		}
		$caught = $null
		try {
			Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue
		}
		catch {
			$caught = $_
		}
		$caught | Should -Not -BeNullOrEmpty
		if ($EarlierError) {
			$caught.Exception.Message | Should -Match 'checkpoint interruption'
		}
		else {
			$caught.Exception.Message | Should -Match 'Intentional (disable|restore) interruption'
		}
		if ($Fault -eq 'restore') {
			$entries = $caught.Exception.Data['Fast1Archiving.CleanupFailures']
			$entries.ConstraintName | Should -Contain "FK_$($script:tableName)_a"
			$entries.DatabaseName | Should -Contain $script:sourceDatabase
		}
		InModuleScope ArchivingModel {
			@($script:constraintAttempts | Where-Object { $_ -like '*:False' }).Count | Should -Be 2
			$script:constraintFault = ''
		}
		$fks = @(Get-ArchivingTestForeignKey)
		($fks | Where-Object { $_.name.EndsWith('_b') }).is_disabled | Should -BeFalse
		$state = Get-ArchivingTestState
		$state.PurgeCompleteDate | Should -BeNullOrEmpty
		$state.CompleteDate | Should -BeNullOrEmpty
		$state.WorkingSetExists | Should -Be 1
		Save-ArchivingTestEvidence -Stage "FK $Fault; earlier operation failure=$EarlierError"
		foreach ($injection in $script:injections) {
			Invoke-ArchivingTestSql -ConnectionString $injection.ConnectionString -Query $injection.Query
		}
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		(Get-ArchivingTestState).CompleteDate | Should -Not -BeNullOrEmpty
		@(Get-ArchivingTestForeignKey | Where-Object is_disabled).Count | Should -Be 0
	}

	It 'preserves <Mode> configuration and no-work behavior' -ForEach @(
		@{ Mode = 'archive only'; Archive = 1; Purge = 0; Active = 1; Empty = 0; SourceRows = 5; DestinationRows = 5; States = 1 }
		@{ Mode = 'purge only'; Archive = 0; Purge = 1; Active = 1; Empty = 0; SourceRows = 0; DestinationRows = 0; States = 1 }
		@{ Mode = 'inactive'; Archive = 1; Purge = 1; Active = 0; Empty = 0; SourceRows = 5; DestinationRows = 0; States = 0 }
		@{ Mode = 'both disabled'; Archive = 0; Purge = 0; Active = 1; Empty = 0; SourceRows = 5; DestinationRows = 0; States = 0 }
		@{ Mode = 'empty capture'; Archive = 1; Purge = 1; Active = 1; Empty = 1; SourceRows = 5; DestinationRows = 0; States = 1 }
	) {
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query @'
update dbo.SourceTable set Archive = @archive, Purge = @purge, Active = @active,
KeyQuery = KeyQuery + case when @empty = 1 then N' where 1 = 0' else N'' end
where TableName = @table_name;
'@ -Parameters @{ archive = $Archive; purge = $Purge; active = $Active; empty = $Empty; table_name = $script:tableName }
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be $SourceRows
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "if object_id(N'dbo.$script:tableName', N'U') is null select 0; else select count(*) from dbo.[$script:tableName]" | Should -Be $DestinationRows
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query @'
select count(*) from dbo.ProcessState ps join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
where st.TableName = @table_name and ps.CompleteDate is not null;
'@ -Parameters @{ table_name = $script:tableName } | Should -Be $States
	}

	It 'recaptures an unconfirmed partial key set after a real partial bulk write' {
		InModuleScope ArchivingModel {
			$script:captureFault = $true
			Mock Get-ArchivingBulkCopy {
				param ($Connection, [Microsoft.Data.SqlClient.SqlBulkCopyOptions]$Options = 0)
				$bulk = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($Connection, $Options, $null)
				if ($script:captureFault) {
					$bulk | Add-Member -MemberType ScriptMethod -Name WriteToServer -Force -Value {
						param ([System.Data.IDataReader]$Reader)
						$partial = [System.Data.DataTable]::new()
						[void]$partial.Columns.Add('Id', [int])
						for ($index = 0; $index -lt 2 -and $Reader.Read(); $index++) {
							[void]$partial.Rows.Add($Reader['Id'])
						}
						$this.psbase.WriteToServer($partial)
						throw 'Intentional partial capture interruption'
					}
				}
				$bulk
			}
		}
		{ Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue } | Should -Throw '*partial capture interruption*'
		(Get-ArchivingTestState).KeyCopyDate | Should -BeNullOrEmpty
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query "select count(*) from dbo.[dbo_$($script:tableName)__src]" | Should -Be 2
		InModuleScope ArchivingModel { $script:captureFault = $false }
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		(Get-ArchivingTestState).KeyMaxValue | Should -Be 5
		(Get-ArchivingTestState).RowsArchived | Should -Be 5
		(Get-ArchivingTestState).CompleteDate | Should -Not -BeNullOrEmpty
	}

	It 'reconciles composite captured keys across the parameter bound and rebuilds a partial snapshot' {
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query @"
drop table dbo.[$script:tableName];
create table dbo.[$script:tableName] (
	Id int not null, Code nvarchar(12) not null, Sequence decimal(12,2) not null,
	Value nvarchar(100) not null, constraint [PK_$script:tableName] primary key(Code, Sequence)
);
"@
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query @"
insert dbo.[$script:tableName](Id, Code, Sequence, Value)
select value * 7, concat(N'key', value * 17), value * 11.25, N'eligible' from generate_series(1, 1105);
"@
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "update dbo.SourceTable set DataCopyBatchSize = 200, PurgeBatchSize = 300, KeyCopyBatchSize = 5000, AlwaysRunCheck = 1, KeyQuery = N'select Code, Sequence from dbo.[$script:tableName] where Value <> N''excluded''' where TableName = @table_name" -Parameters @{ table_name = $script:tableName }
		Invoke-ArchivingTestCheckpointFault -Condition 'i.LastArchivedKey > isnull(d.LastArchivedKey, 0)'
		{ Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue } | Should -Throw '*checkpoint interruption*'
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be 200
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "update dbo.[$script:tableName] set Value = N'excluded' where Id in (select top (1) Id from dbo.[$script:tableName]); insert dbo.[$script:tableName] values (99999, N'outside', 99999.99, N'eligible');"
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Query "update dbo.[$script:tableName] set Value = N'excluded'"
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "drop trigger dbo.[$script:checkpointTrigger]"
		InModuleScope ArchivingModel -Parameters @{ Catalog = $script:configDatabase } {
			$script:snapshotFault = $true
			$script:snapshotCatalog = $Catalog
			Mock Get-ArchivingBulkCopy {
				param ($Connection, [Microsoft.Data.SqlClient.SqlBulkCopyOptions]$Options = 0)
				$bulk = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($Connection, $Options, $null)
				if ($script:snapshotFault -and $Connection.Database -eq $script:snapshotCatalog) {
					$bulk | Add-Member -MemberType ScriptMethod -Name WriteToServer -Force -Value {
						param ([System.Data.IDataReader]$Reader)
						$this.psbase.WriteToServer($Reader)
						throw 'Intentional partial snapshot interruption'
					}
				}
				$bulk
			}
		}
		{ Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue } | Should -Throw '*partial snapshot interruption*'
		(Get-ArchivingTestState).LastArchivedKey | Should -Be 0
		(Get-ArchivingTestState).WorkingSetExists | Should -Be 1
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query "select count(*) from dbo.[dbo_$($script:tableName)__dst]" | Should -BeGreaterThan 0
		InModuleScope ArchivingModel { $script:snapshotFault = $false }
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName]" | Should -Be 1105
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from (select Code, Sequence from dbo.[$script:tableName] group by Code, Sequence) k" | Should -Be 1105
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from generate_series(1, 1105) e left join dbo.[$script:tableName] d on d.Code = concat(N'key', e.value * 17) and d.Sequence = e.value * 11.25 where d.Code is null" | Should -Be 0
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName] where Code = N'outside'" | Should -Be 0
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName] where Id <> 99999" | Should -Be 0
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from dbo.[$script:tableName] where Id = 99999" | Should -Be 1
		(Get-ArchivingTestState).KeyMaxValue | Should -Be 1105
		Write-Information "Composite fixture $($script:groupName): captured 1105, committed before checkpoint 200, page bound 1000, completed destination 1105 unique keys, retained outside key 99999." -InformationAction Continue
	}

	It 'preserves earlier table completion when a later table fails' {
		$laterName = "$($script:tableName)_later"
		foreach ($connectionString in @($script:sourceConnectionString, $script:destinationConnectionString)) {
			$script:injections.Add(@{ ConnectionString = $connectionString; Query = "drop table if exists dbo.[$laterName]" })
		}
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "select * into dbo.[$laterName] from dbo.[$script:tableName]; alter table dbo.[$laterName] add constraint [PK_$laterName] primary key(Id);"
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Query "create table dbo.[$laterName](Id int not null primary key, Value nvarchar(100) not null); insert dbo.[$laterName] values (3, N'three');"
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query @"
update dbo.SourceTable set Purge = 0, AlwaysRunCheck = 1 where TableName = @table_name;
insert dbo.SourceTable(TableGroupId, SchemaName, TableName, Active, DataCopyBatchSize, KeyCopyBatchSize, PurgeBatchSize, KeyQuery, Archive, Purge, PurgeOrder, DelayInterval, AlwaysRunCheck)
select TableGroupId, SchemaName, @later_name, Active, DataCopyBatchSize, KeyCopyBatchSize, PurgeBatchSize,
N'select Id from dbo.[$laterName]', 1, 1, 2, DelayInterval, 0
from dbo.SourceTable where TableName = @table_name;
"@ -Parameters @{ table_name = $script:tableName; later_name = $laterName }
		{ Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue } | Should -Throw '*duplicate key*'
		$completedId = Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query @'
select ps.ProcessStateId from dbo.ProcessState ps join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
where st.TableName = @table_name and ps.CompleteDate is not null;
'@ -Parameters @{ table_name = $script:tableName }
		$completedId | Should -BeGreaterThan 0
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query @'
select count(*) from dbo.ProcessState ps join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
where st.TableName = @later_name and ps.CompleteDate is null;
'@ -Parameters @{ later_name = $laterName } | Should -Be 1
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Scalar -Query 'select count(*) from dbo.ProcessState where ProcessStateId = @id and CompleteDate is not null' -Parameters @{ id = $completedId } | Should -Be 1
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from dbo.[$laterName]" | Should -Be 5
		Write-Information "Multi-table fixture $($script:groupName): earlier completed process $completedId retained while later process retried to five unique archive keys." -InformationAction Continue
	}

	It 'creates a missing destination schema using the configured source schema' {
		$schemaName = "schema_$script:tableName"
		foreach ($connectionString in @($script:sourceConnectionString, $script:destinationConnectionString)) {
			$script:injections.Add(@{ ConnectionString = $connectionString; Query = "drop table if exists [$schemaName].[$script:tableName]; if schema_id(N'$schemaName') is not null exec(N'drop schema [$schemaName]');" })
		}
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Query "exec(N'create schema [$schemaName]'); alter schema [$schemaName] transfer dbo.[$script:tableName];"
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query "update dbo.SourceTable set SchemaName = @schema_name, KeyQuery = N'select Id from [$schemaName].[$script:tableName]' where TableName = @table_name" -Parameters @{ schema_name = $schemaName; table_name = $script:tableName }
		Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName
		Invoke-ArchivingTestSql -ConnectionString $script:destinationConnectionString -Scalar -Query "select count(*) from [$schemaName].[$script:tableName]" | Should -Be 5
		Invoke-ArchivingTestSql -ConnectionString $script:sourceConnectionString -Scalar -Query "select count(*) from [$schemaName].[$script:tableName]" | Should -Be 0
	}

	It 'does not acquire or toggle FK scope with DisableFK off' {
		Initialize-ArchivingTestForeignKey
		Invoke-ArchivingTestSql -ConnectionString $script:configConnectionString -Query 'update dbo.TableGroup set DisableFK = 0 where Name = @group_name' -Parameters @{ group_name = $script:groupName }
		InModuleScope ArchivingModel {
			Mock Invoke-ArchivingConstraintAction { throw 'Unexpected FK toggle' }
		}
		{ Invoke-Fast1Archiving -ConnStr $script:configConnectionString -GroupName $script:groupName -ErrorAction SilentlyContinue } | Should -Throw '*REFERENCE constraint*'
		InModuleScope ArchivingModel { Should -Invoke Invoke-ArchivingConstraintAction -Exactly -Times 0 }
		$fks = @(Get-ArchivingTestForeignKey)
		($fks | Where-Object { $_.name.EndsWith('_a') }).is_disabled | Should -BeFalse
		($fks | Where-Object { $_.name.EndsWith('_a') }).is_not_trusted | Should -BeFalse
		($fks | Where-Object { $_.name.EndsWith('_b') }).is_disabled | Should -BeTrue
	}

	It 'archives rows, purges the source, and completes the process state' {
		Invoke-Fast1Archiving `
			-ConnStr $script:configConnectionString `
			-GroupName $script:groupName

		$sourceRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$completedStates = Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
select count(*)
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name
	and ps.CompleteDate is not null
	and ps.RowsArchived = 5
	and ps.RowsPurged = 5;
'@ `
			-Parameters @{ group_name = $script:groupName } `
			-Scalar

		$sourceRows | Should -Be 0
		$destinationRows | Should -Be 5
		$completedStates | Should -Be 1
	}

	It 'excludes computed and rowversion columns from the destination' {
		Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query @"
alter table dbo.$script:tableName
	add ValueLength as len(Value),
		RowVersionValue rowversion;
"@

		Invoke-Fast1Archiving `
			-ConnStr $script:configConnectionString `
			-GroupName $script:groupName

		$sourceSpecialColumns = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query @"
select count(*)
from sys.columns
where [object_id] = object_id(N'dbo.$script:tableName')
	and
	(
		[Name] = N'ValueLength' and is_computed = 1
		or [Name] = N'RowVersionValue'
			and system_type_id = type_id(N'timestamp')
	);
"@ `
			-Scalar

		$destinationSpecialColumns = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query @"
select count(*)
from sys.columns
where [object_id] = object_id(N'dbo.$script:tableName')
	and [Name] in (N'ValueLength', N'RowVersionValue');
"@ `
			-Scalar

		$sourceRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$sourceSpecialColumns | Should -Be 2
		$destinationSpecialColumns | Should -Be 0
		$sourceRows | Should -Be 0
		$destinationRows | Should -Be 5
	}

	It 'adds a new source column when the destination table already contains data' {
		Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query @"
create table dbo.$script:tableName
(
	Id int not null constraint PK_$script:tableName primary key,
	Value nvarchar(100) not null
);

insert dbo.$script:tableName(Id, Value) values(1, N'one');
"@

		Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query @"
alter table dbo.$script:tableName
	add NewValue int not null
		constraint DF_$script:tableName`_NewValue default (10);
"@

		Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
update st
set AlwaysRunCheck = 1
from dbo.SourceTable st
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name;
'@ `
			-Parameters @{ group_name = $script:groupName }

		Invoke-Fast1Archiving `
			-ConnStr $script:configConnectionString `
			-GroupName $script:groupName

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$existingRowsWithNull = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName where Id = 1 and NewValue is null" `
			-Scalar

		$copiedRowsWithValue = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName where Id > 1 and NewValue = 10" `
			-Scalar

		$newColumnIsNullable = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query @"
select count(*)
from sys.columns
where [object_id] = object_id(N'dbo.$script:tableName')
	and [Name] = N'NewValue'
	and is_nullable = 1;
"@ `
			-Scalar

		$sourceRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$completedState = Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
select count(*)
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name
	and ps.CompleteDate is not null
	and ps.RowsArchived = 4
	and ps.RowsPurged = 5;
'@ `
			-Parameters @{ group_name = $script:groupName } `
			-Scalar

		$destinationRows | Should -Be 5
		$existingRowsWithNull | Should -Be 1
		$copiedRowsWithValue | Should -Be 4
		$newColumnIsNullable | Should -Be 1
		$sourceRows | Should -Be 0
		$completedState | Should -Be 1
	}

	It 'resumes archiving after a failed data-copy batch' {
		Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query @"
create table dbo.$script:tableName
(
	Id int not null constraint PK_$script:tableName primary key,
	Value nvarchar(100) not null
);

insert dbo.$script:tableName(Id, Value) values(3, N'three');
"@

		{
			Invoke-Fast1Archiving `
				-ConnStr $script:configConnectionString `
				-GroupName $script:groupName `
				-ErrorAction SilentlyContinue
		} | Should -Throw

		$partialState = Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
select count(*)
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name
	and ps.CompleteDate is null
	and ps.LastArchivedKey = 2
	and ps.RowsArchived = 2;
'@ `
			-Parameters @{ group_name = $script:groupName } `
			-Scalar

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$partialState | Should -Be 1
		$destinationRows | Should -Be 3
		(Get-ArchivingTestState).WorkingSetExists | Should -Be 1
		Save-ArchivingTestEvidence -Stage 'retained copy interruption'

		Invoke-Fast1Archiving `
			-ConnStr $script:configConnectionString `
			-GroupName $script:groupName

		$sourceRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$completedState = Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
select count(*)
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name
	and ps.CompleteDate is not null
	and ps.RowsArchived = 4
	and ps.RowsPurged = 5;
'@ `
			-Parameters @{ group_name = $script:groupName } `
			-Scalar

		$sourceRows | Should -Be 0
		$destinationRows | Should -Be 5
		$completedState | Should -Be 1
	}

	It 'resumes purging after a failed delete batch' {
		Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query @"
create trigger dbo.TR_$script:tableName`_Interrupt
on dbo.$script:tableName
after delete
as
begin
	set nocount on;

	if exists (select 1 from deleted where Id >= 3)
		throw 51000, 'Intentional purge interruption', 1;
end;
"@

		{
			Invoke-Fast1Archiving `
				-ConnStr $script:configConnectionString `
				-GroupName $script:groupName `
				-ErrorAction SilentlyContinue
		} | Should -Throw '*Intentional purge interruption*'

		$partialState = Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
select count(*)
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name
	and ps.CompleteDate is null
	and ps.LastArchivedKey = 6
	and ps.RowsArchived = 5
	and ps.LastPurgedKey = 2
	and ps.RowsPurged = 2;
'@ `
			-Parameters @{ group_name = $script:groupName } `
			-Scalar

		$sourceRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$partialState | Should -Be 1
		$sourceRows | Should -Be 3
		$destinationRows | Should -Be 5
		(Get-ArchivingTestState).WorkingSetExists | Should -Be 1
		Save-ArchivingTestEvidence -Stage 'retained delete interruption'

		Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "drop trigger dbo.TR_$script:tableName`_Interrupt"

		Invoke-Fast1Archiving `
			-ConnStr $script:configConnectionString `
			-GroupName $script:groupName

		$sourceRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:sourceConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$destinationRows = Invoke-ArchivingTestSql `
			-ConnectionString $script:destinationConnectionString `
			-Query "select count(*) from dbo.$script:tableName" `
			-Scalar

		$completedState = Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @'
select count(*)
from dbo.ProcessState ps
join dbo.SourceTable st on st.SourceTableId = ps.SourceTableId
join dbo.TableGroup tg on tg.TableGroupId = st.TableGroupId
where tg.[Name] = @group_name
	and ps.CompleteDate is not null
	and ps.RowsArchived = 5
	and ps.RowsPurged = 5;
'@ `
			-Parameters @{ group_name = $script:groupName } `
			-Scalar

		$sourceRows | Should -Be 0
		$destinationRows | Should -Be 5
		$completedState | Should -Be 1
	}
}
