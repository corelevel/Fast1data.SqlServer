using module ../shared/EasySqlParam.psm1
using module ./Metadata.psm1
using namespace System.Collections.Generic

. "$PSScriptRoot\..\shared\Invoke-EasySqlQuery.ps1"
. "$PSScriptRoot\Get-DelayIntervalInSecond.ps1"

class TableGroup : System.IDisposable {
	[int]$Id
	[string]$Name

	[string]$SrcServerName
	[string]$SrcDatabaseName

	[string]$DstServerName
	[string]$DstDatabaseName

	[bool]$DisableFK

	[Microsoft.Data.SqlClient.SqlConnection]$ArcSqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
	[Microsoft.Data.SqlClient.SqlConnection]$SrcSqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
	[Microsoft.Data.SqlClient.SqlConnection]$DstSqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()

	[List[Table]]$SourceTables = [List[Table]]::new()

	TableGroup([string]$ConnStr, [string]$groupName) {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sb = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnStr)

			$this.ArcSqlConn.ConnectionString = $sb.ConnectionString
			$this.ArcSqlConn.Open()

			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_GetTableGroup', $this.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pName = $sqlCmd.Parameters.Add('@Name', [System.Data.SqlDbType]::NVarChar)
			$pName.Value = $groupName

			$sqlReader = $sqlCmd.ExecuteReader()
			
			if ($sqlReader.Read()) {
				$this.Id = $sqlReader['TableGroupId']
				$this.Name = $groupName

				# source database server
				$this.SrcServerName = $sqlReader['SrcServerName']
				$this.SrcDatabaseName = $sqlReader['SrcDatabaseName']

				$sb = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($sqlReader['SrcConnOptions'])
				$sb['Data Source'] = $this.SrcServerName
				$sb['Initial Catalog'] = $this.SrcDatabaseName
				$this.SrcSqlConn.ConnectionString = $sb.ConnectionString
				$this.SrcSqlConn.Open()

				# destination database server
				$this.DstServerName = $sqlReader['DstServerName']
				$this.DstDatabaseName = $sqlReader['DstDatabaseName']

				$sb = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($sqlReader['DstConnOptions'])
				$sb['Data Source'] = $this.DstServerName
				$sb['Initial Catalog'] = $this.DstDatabaseName
				$sb['Persist Security Info'] = 'True'
				$this.DstSqlConn.ConnectionString = $sb.ConnectionString
				$this.DstSqlConn.Open()

				$this.DisableFK = $sqlReader['DisableFK']
			}
		}
		finally {
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	ReadSourceTables() {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_GetSourceTable', $this.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pTableGroupId = $sqlCmd.Parameters.Add('@TableGroupId', [System.Data.SqlDbType]::Int)
			$pTableGroupId.Value = $this.Id

			$sqlReader = $sqlCmd.ExecuteReader()
			while ($sqlReader.Read()) {
				$this.SourceTables.Add(
					[Table]@{
						Id = $sqlReader['SourceTableId']
						SchemaName = $sqlReader['SchemaName']
						TableName = $sqlReader['TableName']
						DataCopyBatchSize = $sqlReader['DataCopyBatchSize']
						KeyCopyBatchSize = $sqlReader['KeyCopyBatchSize']
						PurgeBatchSize = $sqlReader['PurgeBatchSize']
						KeyQuery = $sqlReader['KeyQuery']
						Archive = $sqlReader['Archive']
						Purge = $sqlReader['Purge']
						PurgeOrder = $sqlReader['PurgeOrder']
						DelayIntervalInSeconds = Get-DelayIntervalInSecond -DelayInterval $sqlReader['DelayInterval']
						AlwaysRunCheck = $sqlReader['AlwaysRunCheck']
						SrcWorkingTableName = $sqlReader['SrcWorkingTableName']
						DstWorkingTableName = $sqlReader['DstWorkingTableName']
						WorkingTableKeyName = $sqlReader['WorkingTableKeyName']
						WorkingTableFlagName = $sqlReader['WorkingTableFlagName']
						Group = $this
					}
				)
			}
		}
		finally {
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	Dispose() {
        $this.ArcSqlConn?.Dispose()
        $this.SrcSqlConn?.Dispose()
        $this.DstSqlConn?.Dispose()
    }
}

class ProcessState {
	[int]$Id
	[int]$SourceTableId
	[DateTime]$CreateDate

	[DateTime]$KeyCopyDate
	[int]$KeyMaxValue

	[int]$LastArchivedKey
	[DateTime]$ArchiveCompleteDate
	[int]$RowsArchived

	[int]$LastPurgedKey
	[DateTime]$PurgeCompleteDate
	[int]$RowsPurged

	[DateTime]$CompleteDate

	[bool]$IncompleteProcess

	[int]$RowsArchivedForBatch
	[int]$RowsPurgedForBatch

	[Microsoft.Data.SqlClient.SqlConnection]$ArcSqlConn

	UpdateKeyMaxValue() {
		$this.KeyMaxValue = [int](Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateKeyMaxValue' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
			} `
			-Scalar
		)
	}

	UpdateKeyCopyDate() {
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				KeyCopyDate = [EasySqlParam]@{
					Value = [DateTime]::Now
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
	}

	UpdateCompleteDate() {
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				CompleteDate = [EasySqlParam]@{
					Value = [DateTime]::Now
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
	}

	UpdateArchiveComplete() {
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastArchivedKey = [EasySqlParam]@{
					Value = $this.LastArchivedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsArchived = [EasySqlParam]@{
					Value = $this.RowsArchived
					Type  = [System.Data.SqlDbType]::Int
				}
				ArchiveCompleteDate = [EasySqlParam]@{
					Value = [DateTime]::Now
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
	}

	UpdateArchiveState() {
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastArchivedKey = [EasySqlParam]@{
					Value = $this.LastArchivedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsArchived = [EasySqlParam]@{
					Value = $this.RowsArchived
					Type  = [System.Data.SqlDbType]::Int
				}
			}
	}

	UpdatePurgeComplete() {
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastPurgedKey = [EasySqlParam]@{
					Value = $this.LastPurgedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsPurged = [EasySqlParam]@{
					Value = $this.RowsPurged
					Type  = [System.Data.SqlDbType]::Int
				}
				PurgeCompleteDate = [EasySqlParam]@{
					Value = [DateTime]::Now
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
	}

	UpdatePurgeState() {
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastPurgedKey = [EasySqlParam]@{
					Value = $this.LastPurgedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsPurged = [EasySqlParam]@{
					Value = $this.RowsPurged
					Type  = [System.Data.SqlDbType]::Int
				}
			}
	}

	Create() {
		if ($this.Id -ne 0) {
			throw 'State.Id already has a value'
		}
		$this.Id = [int](Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_InsertProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				SourceTableId = [EasySqlParam]@{
					Value = $this.SourceTableId
					Type  = [System.Data.SqlDbType]::Int
				}
			} `
			-Scalar
		)
	}

	[bool]ArchiveProcessHasRowsForNextBatch() {
		return ($this.LastArchivedKey -lt $this.KeyMaxValue)
	}

	[bool]PurgeProcessHasRowsForNextBatch() {
		return ($this.LastPurgedKey -lt $this.KeyMaxValue)
	}

	[bool]IsPkCopied() {
		return ($this.KeyCopyDate -ne [DateTime]::MinValue)
	}

	[bool]FixAndGetLastArchivedKey() {
		$newLastArchivedKey = [int](Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_FixLastArchivedKey' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
			} `
			-Scalar
		)
		if ($this.LastArchivedKey -ne $newLastArchivedKey) {
			$this.LastArchivedKey = $newLastArchivedKey
			return $true
		}
		return $false
	}

	SetBulkRowsCopied($count) {
		$this.RowsArchivedForBatch = [int]$count
	}
}

class Table {
	[int]$Id
	[string]$SchemaName
	[string]$TableName
	[int]$DataCopyBatchSize
	[int]$KeyCopyBatchSize
	[int]$PurgeBatchSize
	[string]$KeyQuery
	[bool]$Archive
	[bool]$Purge
	[int]$PurgeOrder
	[int]$DelayIntervalInSeconds
	[bool]$AlwaysRunCheck
	[string]$SrcWorkingTableName
	[string]$DstWorkingTableName
	[string]$WorkingTableKeyName
	[string]$WorkingTableFlagName

	[TableGroup]$Group
	[ProcessState]$State
	[Dictionary[string, TableColumn]]$SrcColumns
	[Index]$SrcPk
	[Index]$SrcCl
	[List[IndexColumn]]$SrcPkColumns
	[List[IndexColumn]]$SrcClColumns
	[Dictionary[string, TableColumn]]$DstColumns
	[Index]$DstPk
	[Index]$DstCl
	[List[IndexColumn]]$DstPkColumns
	[List[IndexColumn]]$DstClColumns
	[List[TableColumn]]$MissedColumns = [List[TableColumn]]::new()
	[bool]$FKDisabled = $false

	GetState() {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$this.State = [ProcessState]@{
				SourceTableId = $this.Id
				ArcSqlConn = $this.Group.ArcSqlConn
				IncompleteProcess = $false
			}

			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_GetIncompleteProcessState', $this.Group.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pSourceTableId = $sqlCmd.Parameters.Add('@SourceTableId', [System.Data.SqlDbType]::Int, 128)
			$pSourceTableId.Value = $this.Id

			$sqlReader = $sqlCmd.ExecuteReader()

			if ($sqlReader.Read()) {
				$this.State.Id = $sqlReader['ProcessStateId']

				if ($sqlReader['KeyCopyDate'] -isnot [System.DBNull]) {
					$this.State.KeyCopyDate = $sqlReader['KeyCopyDate']
				}
				if ($sqlReader['KeyMaxValue'] -isnot [System.DBNull]) {
					$this.State.KeyMaxValue = $sqlReader['KeyMaxValue']
				}
				if ($sqlReader['LastArchivedKey'] -isnot [System.DBNull]) {
					$this.State.LastArchivedKey = $sqlReader['LastArchivedKey']
				}
				if ($sqlReader['ArchiveCompleteDate'] -isnot [System.DBNull]) {
					$this.State.ArchiveCompleteDate = $sqlReader['ArchiveCompleteDate']
				}
				if ($sqlReader['RowsArchived'] -isnot [System.DBNull]) {
					$this.State.RowsArchived = $sqlReader['RowsArchived']
				}
				if ($sqlReader['LastPurgedKey'] -isnot [System.DBNull]) {
					$this.State.LastPurgedKey = $sqlReader['LastPurgedKey']
				}
				if ($sqlReader['PurgeCompleteDate'] -isnot [System.DBNull]) {
					$this.State.PurgeCompleteDate = $sqlReader['PurgeCompleteDate']
				}
				if ($sqlReader['RowsPurged'] -isnot [System.DBNull]) {
					$this.State.RowsPurged = $sqlReader['RowsPurged']
				}

				$this.State.IncompleteProcess = $true
			}
		}
		finally {
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	[bool]IsTableExistsInSource() {
		return [Table]::IsTableExists($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
	}

	[bool]IsTableExistsInDestination() {
		return [Table]::IsTableExists($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
	}

	[bool]IsTableSchemaExistsInDestination() {
		return [Table]::IsTableSchemaExists($this.SchemaName, $this.Group.DstSqlConn)
	}

	static [bool]IsTableExists([string]$schemaName, [string]$tableName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @'
set nocount on
select	case when exists
			(
			select	1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_SCHEMA = @SchemaName
				and TABLE_NAME = @TableName
				and TABLE_TYPE = 'BASE TABLE'
			)
			then 1
			else 0
		end v
'@
		return [bool](Invoke-EasySqlQuery `
			-SqlConn $sqlConnection `
			-Query $query `
			-Parameters @{
				SchemaName = [EasySqlParam]@{
					Value = $schemaName
					Type  = [System.Data.SqlDbType]::NVarChar
					Size  = 128
				}
				TableName = [EasySqlParam]@{
					Value = $tableName
					Type  = [System.Data.SqlDbType]::NVarChar
					Size  = 128
				}
			} `
			-Scalar
		)
	}

	static [bool]IsTableSchemaExists([string]$schemaName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @'
set nocount on
select case when exists (select	1 from sys.schemas where [name] = @SchemaName) then 1 else 0 end v
'@
		return [bool](Invoke-EasySqlQuery `
			-SqlConn $sqlConnection `
			-Query $query `
			-Parameters @{
				SchemaName = [EasySqlParam]@{
					Value = $schemaName
					Type  = [System.Data.SqlDbType]::NVarChar
					Size  = 128
				}
			} `
			-Scalar
		)
	}

	static [string]GetColumnDefinition([TableColumn]$c) {
		$col = "[$($c.Name)] $($c.DataType)"
		if ($c.Collation) {
			$col += " collate $($c.Collation)"
		}
		$col += if ($c.Nullable) { ' null' } else { ' not null' }
		return $col
	}

	ReadSrcTableColumns() {
		$this.SrcColumns = [Table]::GetTableColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcPk = [Table]::GetTablePrimaryKeyIndex($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcCl = [Table]::GetTableClusteredIndex($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcPkColumns = [Table]::GetTablePrimaryColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
		$this.SrcClColumns = [Table]::GetTableClusteredColumns($this.SchemaName, $this.TableName, $this.Group.SrcSqlConn)
	}

	ReadDstTableColumns() {
		$this.DstColumns = [Table]::GetTableColumns($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstPk = [Table]::GetTablePrimaryKeyIndex($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstCl = [Table]::GetTableClusteredIndex($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstPkColumns = [Table]::GetTablePrimaryColumns($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
		$this.DstClColumns = [Table]::GetTableClusteredColumns($this.SchemaName, $this.TableName, $this.Group.DstSqlConn)
	}

	static [Dictionary[string, TableColumn]] GetTableColumns([string]$schemaName, [string]$tableName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @'
set nocount on
select	COLUMN_NAME [Name],
		DATA_TYPE +
			case
				when DATA_TYPE in ('decimal','numeric')
					then '(' + cast(NUMERIC_PRECISION as varchar) + ', ' + cast(NUMERIC_SCALE as varchar) + ')'
				when DATA_TYPE in ('varchar','char','varbinary','binary','nvarchar','nchar')
					then coalesce('(' + case when CHARACTER_MAXIMUM_LENGTH = -1 then 'max' else cast(CHARACTER_MAXIMUM_LENGTH as varchar) end + ')', '') 
				else ''
			end DataType,
        COLLATION_NAME [Collation],
		columnproperty(object_id(TABLE_SCHEMA + '.' + TABLE_NAME), COLUMN_NAME, 'IsComputed') Computed,
		case when IS_NULLABLE = 'YES' then 1 else 0 end Nullable
from	INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = @SchemaName and TABLE_NAME = @TableName
	and DATA_TYPE not in('timestamp','rowversion')
'@

		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($query, $sqlConnection)
			$sqlCmd.Parameters.Add("@SchemaName", [System.Data.SqlDbType]::NVarChar, 128).Value = $schemaName
			$sqlCmd.Parameters.Add("@TableName", [System.Data.SqlDbType]::NVarChar, 128).Value = $tableName
			$sqlReader = $sqlCmd.ExecuteReader()
			$columns = [Dictionary[string, TableColumn]]::new([System.StringComparer]::OrdinalIgnoreCase)

			while ($sqlReader.Read()) {
				$columns[$sqlReader['Name']] = ([TableColumn]@{
					Name = $sqlReader['Name']
					DataType = $sqlReader['DataType']
					Collation = if ($sqlReader['Collation'] -isnot [System.DBNull]) { $sqlReader['Collation'] } else { $null }
					Computed = $sqlReader['Computed']
					Nullable = $sqlReader['Nullable']
				})
			}
			return $columns
		}
		finally {
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	static [List[IndexColumn]] GetTableClusteredColumns([string]$schemaName, [string]$tableName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @"
set nocount on
select	ic.index_column_id ColumnId,
		c.[name] ColumnName,
		case when ic.is_descending_key = 1 then 'desc' else 'asc' end [Order]
from	sys.indexes i
		join sys.index_columns ic
		on ic.[object_id] = i.[object_id] and ic.index_id = i.index_id
		join sys.columns c
		on c.[object_id] = ic.[object_id] and c.column_id = ic.column_id
where i.[object_id] = object_id(@ObjectName)
  and i.[type] = 1
  and ic.key_ordinal > 0
"@

		return [Table]::GetTableIndexColumns($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [List[IndexColumn]] GetTablePrimaryColumns([string]$schemaName, [string]$tableName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @"
set nocount on
select	ic.key_ordinal ColumnId,
		c.[name] ColumnName,
		case when ic.is_descending_key = 1 then 'desc' else 'asc' end [Order]
from	sys.key_constraints kc
		join sys.indexes i
		on i.[object_id] = kc.parent_object_id and i.index_id = kc.unique_index_id
		join sys.index_columns ic 
		on ic.[object_id] = i.[object_id] and ic.index_id = i.index_id
		JOIN sys.columns c 
		on c.[object_id] = ic.[object_id] and c.column_id = ic.column_id
where kc.[type] = 'PK'
  and kc.parent_object_id = object_id(@ObjectName)
"@

		return [Table]::GetTableIndexColumns($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [List[IndexColumn]] GetTableIndexColumns([string]$query, [string]$objectName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($query, $sqlConnection) 
			$sqlCmd.Parameters.Add("@ObjectName", [System.Data.SqlDbType]::NVarChar, 257).Value = $objectName
			$sqlReader = $sqlCmd.ExecuteReader()
			$columns = [List[IndexColumn]]::new()

			while ($sqlReader.Read()) {
				$columns.Add([IndexColumn]@{
					Id = $sqlReader['ColumnId']
					Name = $sqlReader['ColumnName']
					Order = $sqlReader['Order']
				})
			}
			return $columns
		}
		finally {
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	static [Index] GetTableClusteredIndex([string]$schemaName, [string]$tableName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @"
set nocount on
select	[name] [Name],
		is_unique [Unique]
from	sys.indexes
where [object_id] = object_id(@ObjectName)
  and [type] = 1
"@

		return [Table]::GetTableIndex($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [Index] GetTablePrimaryKeyIndex([string]$schemaName, [string]$tableName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$query = @"
select	i.[name] [Name],
		i.is_unique [Unique]
from	sys.key_constraints kc
		join sys.indexes i
		on i.[object_id] = kc.parent_object_id and i.index_id = kc.unique_index_id
where kc.[type] = 'PK'
  and kc.parent_object_id = object_id(@ObjectName)
"@

		return [Table]::GetTableIndex($query, "$schemaName.$tableName", $sqlConnection)
	}

	static [Index] GetTableIndex([string]$query, [string]$objectName, [Microsoft.Data.SqlClient.SqlConnection]$sqlConnection) {
		$sqlCmd = $null
		$sqlReader = $null
		try {
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($query, $sqlConnection)
			$sqlCmd.Parameters.Add("@ObjectName", [System.Data.SqlDbType]::NVarChar, 257).Value = $objectName
			$sqlReader = $sqlCmd.ExecuteReader()
			
			if ($sqlReader.Read()) {
				return [Index]@{
					Name = $sqlReader['Name']
					Unique = [bool]$sqlReader['Unique']
				}
			}

			return $null
		}
		finally {
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	[bool]AddMissedColumns() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append("alter table [$($this.SchemaName)].[$($this.TableName)] add ")

		$hasMissed = $false
		foreach($c in $this.SrcColumns.Values.Where({ -not $_.Computed })) {
			if ($this.DstColumns.ContainsKey($c.Name)) {
				continue
			}
			# missed columns are ALWAYS nullable
			if ([string]::IsNullOrEmpty($c.Collation)) {
				$query.Append("[$($c.Name)] $($c.DataType) null,")
			}
			else {
				$query.Append("[$($c.Name)] $($c.DataType) collate $($c.Collation) null,")
			}
			$hasMissed = $true
		}
		if (-not $hasMissed) {
			return $false
		}
		$query.Length -= 1

		Invoke-EasySqlQuery `
			-SqlConn $this.Group.DstSqlConn `
			-Query $query.ToString()
		return $true
	}

	CreateDestinationTable() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append("set xact_abort on  begin tran create table [$($this.SchemaName)].[$($this.TableName)](")

		foreach ($c in $this.SrcColumns.Values.Where({ -not $_.Computed })) {
			$query.Append([Table]::GetColumnDefinition($c) + ',')
		}
		$query.Length -= 1
		$query.Append(') ')

		if ($this.SrcPk.Name -ne $this.SrcCl.Name) {
			if ($this.SrcCl.Unique) {
				$query.Append("create unique clustered ")
			}
			else {
				$query.Append("create clustered index ")
			}
			$query.Append("index [$($this.SrcCl.Name)] on [$($this.SchemaName)].[$($this.TableName)] (")
			foreach ($c in $this.SrcClColumns | Sort-Object -Property Id) {
				$query.Append("[$($c.Name)]  $($c.Order),")
			}
			$query.Length -= 1

			$query.Append("alter table [$($this.SchemaName)].[$($this.TableName)] add constraint $($this.SrcCl.Name) primary key nonclustered (")
			foreach ($c in $this.SrcPkColumns | Sort-Object -Property Id) {
				$query.Append("[$($c.Name)]  $($c.Order),")
			}
			$query.Length -= 1
			$query.Append(') ')
		}
		else {
			$query.Append("alter table [$($this.SchemaName)].[$($this.TableName)] add constraint $($this.SrcPk.Name) primary key clustered (")
			foreach ($c in $this.SrcPkColumns | Sort-Object -Property Id) {
				$query.Append("[$($c.Name)]  $($c.Order),")
			}
			$query.Length -= 1
			$query.Append(') ')
		}
		$query.Append('commit tran')

		Invoke-EasySqlQuery `
			-SqlConn $this.Group.DstSqlConn `
			-Query $query.ToString()
	}

	CreateDestinationTableSchema() {
		$query = "create schema [$($this.SchemaName)]"
		Invoke-EasySqlQuery `
			-SqlConn $this.Group.DstSqlConn `
			-Query $query.ToString()
	}

	DisableEnableFK($disable) {
		if (-not $this.Group.DisableFK) {
			return
		}
		Invoke-EasySqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_DisableEnableFK' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				Disable = [EasySqlParam]@{
					Value = $disable
					Type  = [System.Data.SqlDbType]::Bit
				}
			}

		$this.FKDisabled = $disable
	}

	DropWorkingTables() {
		$query = @"
if exists(	select	1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.SrcWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.SrcWorkingTableName)]
end

if exists(  select  1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.DstWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.DstWorkingTableName)]
end
"@

		Invoke-EasySqlQuery `
			-SqlConn $this.Group.ArcSqlConn `
			-Query $query `
	}

	CreateSourceWorkingTable() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append(@"
if exists(	select	1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.SrcWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.SrcWorkingTableName)]
end
create table dbo.[$($this.SrcWorkingTableName)] ([$($this.WorkingTableKeyName)] int identity(1,1) not null primary key clustered, [$($this.WorkingTableFlagName)] bit not null default 0,
"@)

		foreach ($pkc in $this.SrcPkColumns) {
			$c = $null
			$b = $this.SrcColumns.TryGetValue($pkc.Name, [ref]$c)
			if (-not $b) {
				throw "Primary key column [$($pkc.Name)] not found for [$($this.SchemaName)].[$($this.TableName)] table"
			}
			$query.Append([Table]::GetColumnDefinition($c) + ',')
		}
		$query.Length -= 1
		$query.Append(')')

		Invoke-EasySqlQuery `
			-SqlConn $this.Group.ArcSqlConn `
			-Query $query `
	}

	CreateDestinationWorkingTable() {
		$query = [System.Text.StringBuilder]::new()
		$query.Append(@"
if exists(  select  1
			from	INFORMATION_SCHEMA.TABLES
			where TABLE_NAME = '$($this.DstWorkingTableName)' and TABLE_SCHEMA = 'dbo' and TABLE_TYPE = 'BASE TABLE')
begin
	drop table dbo.[$($this.DstWorkingTableName)]
end
create table dbo.[$($this.DstWorkingTableName)] ([$($this.WorkingTableKeyName)] int identity(1,1) not null primary key clustered,
"@)

		foreach ($pkc in $this.SrcPkColumns) {
			$c = $null
			$b = $this.SrcColumns.TryGetValue($pkc.Name, [ref]$c)
			if (-not $b) {
				throw "Primary key column [$($pkc.Name)] not found for [$($this.SchemaName)].[$($this.TableName)] table"
			}
			$query.Append([Table]::GetColumnDefinition($c) + ',')
		}
		$query.Length -= 1
		$query.Append(')')

		Invoke-EasySqlQuery `
			-SqlConn $this.Group.ArcSqlConn `
			-Query $query `
	}

	BulkCopySourcePK() {
		<#
		.SYNOPSIS
		Copies primary keys from the source database to the working table

		.DESCRIPTION
		Copies primary keys from the source database to the working table using BulkCopy
		#>
		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		try {
			# source
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($this.KeyQuery, $this.Group.SrcSqlConn) 
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$bulkCopy = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($this.Group.ArcSqlConn)

			$bulkCopy.DestinationTableName = $this.SrcWorkingTableName
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.KeyCopyBatchSize
			foreach ($c in $this.SrcPkColumns) {
				[void]$bulkCopy.ColumnMappings.Add([Microsoft.Data.SqlClient.SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		finally {
			if ($null -ne $bulkCopy) {
				$bulkCopy.Dispose()
			}
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	BulkCopyDestinationPK() {
		<#
		.SYNOPSIS
		Copies primary keys from the destination database to the working table

		.DESCRIPTION
		Copies primary keys from the destination database to the working table using BulkCopy
		#>

		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		try {
			# source
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($this.KeyQuery, $this.Group.DstSqlConn) 
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$bulkCopy = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($this.Group.ArcSqlConn)

			$bulkCopy.DestinationTableName = $this.DstWorkingTableName
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.KeyCopyBatchSize
			foreach ($c in $this.SrcPkColumns) {
				[void]$bulkCopy.ColumnMappings.Add([Microsoft.Data.SqlClient.SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		finally {
			if ($null -ne $bulkCopy) {
				$bulkCopy.Dispose()
			}
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	BulkCopyTable() {
		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		try {
			# source
			$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_GetBulkCopyData', $this.Group.ArcSqlConn) 
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.State.Id
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$options = [Microsoft.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity -bor [Microsoft.Data.SqlClient.SqlBulkCopyOptions]::KeepNulls
			$bulkCopy = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($this.Group.DstSqlConn.ConnectionString, $options)

			$bulkCopy.DestinationTableName = "[$($this.SchemaName)].[$($this.TableName)]"
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.DataCopyBatchSize
			$bulkCopy.NotifyAfter = [Math]::Max(1, [int]($this.DataCopyBatchSize / 10))
			$localTable = $this
			$bulkCopy.add_SqlRowsCopied({
				param($s, $e)
				$null = $s
				$localTable.State.SetBulkRowsCopied($e.RowsCopied)
			})

			foreach ($c in $this.SrcColumns.Values.Where({ -not $_.Computed })) {
				[void]$bulkCopy.ColumnMappings.Add([Microsoft.Data.SqlClient.SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		finally {
			if ($null -ne $bulkCopy) {
				$bulkCopy.Dispose()
			}
			if ($null -ne $sqlReader) {
				$sqlReader.Dispose()
			}
			if ($null -ne $sqlCmd) {
				$sqlCmd.Dispose()
			}
		}
	}

	PurgeData() {
		$this.State.RowsPurgedForBatch = [int](Invoke-EasySqlQuery `
			-SqlConn $this.Group.ArcSqlConn `
			-Query 'dbo.stp_PurgeData' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [EasySqlParam]@{
					Value = $this.State.Id
					Type  = [System.Data.SqlDbType]::Int
				}
			} `
			-Scalar
		)
	}
}

