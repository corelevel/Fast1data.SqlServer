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
