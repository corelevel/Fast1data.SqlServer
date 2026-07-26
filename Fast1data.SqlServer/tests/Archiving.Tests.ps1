BeforeAll {
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force

	$script:configConnectionString = @(
		'Data Source=(local)'
		'Initial Catalog=pester_archiving'
		'User ID=pester'
		'Password=pester'
		'Encrypt=False'
		'TrustServerCertificate=True'
		'Application Name=Fast1data.SqlServer.Archiving.Tests'
	) -join ';'

	$script:sourceConnectionString = @(
		'Data Source=(local)'
		'Initial Catalog=pester'
		'User ID=pester'
		'Password=pester'
		'Encrypt=False'
		'TrustServerCertificate=True'
		'Application Name=Fast1data.SqlServer.Archiving.Tests'
	) -join ';'

	$script:destinationConnectionString = @(
		'Data Source=(local)'
		'Initial Catalog=pester_arc'
		'User ID=pester'
		'Password=pester'
		'Encrypt=False'
		'TrustServerCertificate=True'
		'Application Name=Fast1data.SqlServer.Archiving.Tests'
	) -join ';'

	$script:connectionOptions = @(
		'User ID=pester'
		'Password=pester'
		'Encrypt=False'
		'TrustServerCertificate=True'
		'Application Name=Fast1data.SqlServer.Archiving.Tests'
	) -join ';'

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

	$tablesPath = Join-Path $script:moduleRoot 'schema\archiving\tables.sql'
	$sprocsPath = Join-Path $script:moduleRoot 'schema\archiving\sprocs.sql'

	Invoke-ArchivingTestSqlFile `
		-ConnectionString $script:configConnectionString `
		-Path $tablesPath

	Invoke-ArchivingTestSqlFile `
		-ConnectionString $script:configConnectionString `
		-Path $sprocsPath
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
	N'(local)',
	N'pester',
	@connection_options,
	N'(local)',
	N'pester_arc',
	@connection_options,
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
			}
	}

	AfterEach {
		Invoke-ArchivingTestSql `
			-ConnectionString $script:configConnectionString `
			-Query @"
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
			Invoke-ArchivingTestSql `
				-ConnectionString $connectionString `
				-Query @"
if object_id(N'dbo.$script:tableName', N'U') is not null
	drop table dbo.$script:tableName;
"@
		}
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
