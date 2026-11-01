using module ../../private/archiving/ArchivingModel.psm1
using module ../../private/archiving/Metadata.psm1
using module ../../private/shared/GenericSqlParam.psm1

# The worker bootstraps this distribution's SqlClient assembly before parsing this file.
$instances = @(
	[TableGroup]::new('Server=controlled', 'empty')
	[Table]::new()
	[ProcessState]::new()
	[GenericSqlParam]::new()
	[TableColumn]::new()
	[IndexColumn]::new()
	[Index]::new()
)
($instances | ForEach-Object { $_.GetType().Name }) -join ',' | Should -Be 'TableGroup,Table,ProcessState,GenericSqlParam,TableColumn,IndexColumn,Index'
[ProcessState].GetProperty('ArcSqlConn').PropertyType.FullName | Should -Be 'Microsoft.Data.SqlClient.SqlConnection'
foreach ($name in @('Id', 'SourceTableId', 'KeyMaxValue', 'LastArchivedKey', 'RowsArchived', 'LastPurgedKey', 'RowsPurged', 'RowsArchivedForBatch', 'RowsPurgedForBatch')) {
	[ProcessState].GetProperty($name).PropertyType | Should -Be ([int])
}
foreach ($name in @('CreateDate', 'KeyCopyDate', 'ArchiveCompleteDate', 'PurgeCompleteDate', 'CompleteDate')) {
	[ProcessState].GetProperty($name).PropertyType | Should -Be ([datetime])
}
[ProcessState].GetProperty('IncompleteProcess').PropertyType | Should -Be ([bool])
$column = [TableColumn]@{ Name = 'Id'; DataType = 'int'; SqlSize = 4; SqlPrecision = 10; SqlScale = 0; Nullable = $false }
$column.Name | Should -Be 'Id'
$indexColumn = [IndexColumn]@{ Id = 1; Name = 'Id'; Order = 'asc' }
$indexColumn.Order | Should -Be 'asc'
$index = [Index]@{ Name = 'PK'; Unique = $true }
$index.Unique | Should -BeTrue
$sourceColumns = [System.Collections.Generic.Dictionary[string, TableColumn]]::new()
$targetColumns = [System.Collections.Generic.Dictionary[string, TableColumn]]::new()
$sourceColumns.Add('Id', $column)
$targetColumns.Add('Id', [TableColumn]@{ Name = 'Id'; DataType = 'int'; SqlSize = 4; SqlPrecision = 10; SqlScale = 0; Nullable = $false })
$model = Get-Module ArchivingModel
@(& $model {
	param ($Source, $Target)
	Compare-Column -SrcColumns $Source -DstColumns $Target
} $sourceColumns $targetColumns) | Should -HaveCount 0
$targetColumns['Id'].DataType = 'bigint'
{ & $model {
	param ($Source, $Target)
	Compare-Column -SrcColumns $Source -DstColumns $Target
} $sourceColumns $targetColumns } | Should -Throw '*data type*'
foreach ($consumer in @((Get-Module Fast1data.SqlServer), $model)) {
	$descriptor = & $consumer {
		[GenericSqlParam]@{ Value = 12; Type = [System.Data.SqlDbType]::Decimal; Size = 8; Precision = 12; Scale = 2 }
	}
	$descriptor | Should -BeOfType ([GenericSqlParam])
	$descriptor.Value | Should -Be 12
	$descriptor.Type | Should -Be ([System.Data.SqlDbType]::Decimal)
	$descriptor.Size | Should -Be 8
	$descriptor.Precision | Should -Be 12
	$descriptor.Scale | Should -Be 2
}
foreach ($preference in @($null, [System.Management.Automation.ActionPreference]::Continue, [System.Management.Automation.ActionPreference]::SilentlyContinue)) {
	$group = [TableGroup]::new('Server=controlled', 'empty')
	$VerbosePreference = 'SilentlyContinue'
	$records = @(& {
		if ($null -eq $preference) {
			$group.Execute()
		}
		else {
			$group.Execute($preference)
		}
	} 4>&1)
	$expectedCount = 0
	if ($preference -eq [System.Management.Automation.ActionPreference]::Continue) {
		$expectedCount = 2
	}
	$records.Count | Should -Be $expectedCount
	{ $group.Execute() } | Should -Throw '*single-use*'
	{ $group.Execute([System.Management.Automation.ActionPreference]::Continue) } | Should -Throw '*single-use*'
}
