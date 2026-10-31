using module ../shared/GenericSqlParam.psm1
using module ./Metadata.psm1
using namespace System.Collections.Generic

. "$PSScriptRoot\..\shared\GenericSqlQuery.ps1"
. "$PSScriptRoot\Get-DelayIntervalInSecond.ps1"
. "$PSScriptRoot\Compare-Column.ps1"
. "$PSScriptRoot\..\shared\Write-LogMessage.ps1"

function Get-ArchivingConnection {
	param ([string]$ConnectionString, [string]$Role)
	$null = $Role
	[Microsoft.Data.SqlClient.SqlConnection]::new($ConnectionString)
}

function Get-ArchivingCommand {
	param ([string]$Query, $Connection)
	[Microsoft.Data.SqlClient.SqlCommand]::new($Query, $Connection)
}

function Get-ArchivingTable {
	param ([hashtable]$Values)
	[Table]$Values
}

function Get-ArchivingBulkCopy {
	param ($Connection, [Microsoft.Data.SqlClient.SqlBulkCopyOptions]$Options = 0)
	[Microsoft.Data.SqlClient.SqlBulkCopy]::new($Connection, $Options, $null)
}

function Get-ArchivingServerIdentity {
	param ($Connection)
	Invoke-GenericSqlQuery -SqlConn $Connection -Query "select cast(serverproperty('ServerName') as nvarchar(128))" -Scalar
}

function ConvertTo-ArchivingIdentifier {
	param ([string]$Name)
	if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 128 -or $Name.Contains([char]0)) {
		throw 'A SQL identifier must contain between 1 and 128 characters and no null characters.'
	}
	'[' + $Name.Replace(']', ']]') + ']'
}

function Invoke-ArchivingConstraintAction {
	param ($Connection, $Constraint, [bool]$Disable)
	$database = ConvertTo-ArchivingIdentifier $Constraint.DatabaseName
	$schema = ConvertTo-ArchivingIdentifier $Constraint.SchemaName
	$table = ConvertTo-ArchivingIdentifier $Constraint.TableName
	$name = ConvertTo-ArchivingIdentifier $Constraint.ConstraintName
	$action = if ($Disable) {
		'nocheck'
	}
	else {
		'with nocheck check'
	}
	Invoke-GenericSqlQuery -SqlConn $Connection -Query "alter table $database.$schema.$table $action constraint $name"
}

class TableGroup : System.IDisposable {
	[int]$Id
	[string]$Name

	[string]$SrcServerName
	[string]$SrcDatabaseName

	[string]$DstServerName
	[string]$DstDatabaseName

	[bool]$DisableFK

	hidden [object]$ArcSqlConn
	hidden [object]$SrcSqlConn
	hidden [object]$DstSqlConn
	hidden [string]$ConnectionString
	hidden [bool]$Started

	[List[Table]]$SourceTables = [List[Table]]::new()

	TableGroup([string]$ConnStr, [string]$groupName) {
		$this.ConnectionString = $ConnStr
		$this.Name = $groupName
	}

	Execute() {
		if ($this.Started) {
			throw 'A table group execution is single-use. Retry with a fresh execution.'
		}
		$this.Started = $true
		$operationError = $null
		try {
			$this.Initialize()
			if ($this.Id -eq 0) {
				throw "Specified table group ($($this.Name)) not found"
			}
			Write-LogMessage -Message "Archive group ($($this.Name)) found"
			$this.ReadSourceTables()
			if ($this.SourceTables.Count -eq 0) {
				Write-LogMessage -Message "No tables found for the specified table group ($($this.Name))"
			}
			foreach ($table in $this.SourceTables) {
				if (-not $table.Archive -and -not $table.Purge) {
					continue
				}
				$table.Prepare()
				if ($table.Archive) {
					$table.ExecuteArchive()
				}
			}
			foreach ($table in $this.SourceTables | Where-Object Purge | Sort-Object PurgeOrder) {
				$table.ExecutePurge()
			}
		}
		catch {
			$operationError = $_
			# Normalize nested SQL cleanup entries at the execution boundary.
			$entries = [List[object]]::new()
			foreach ($entry in @(Get-GenericSqlCleanupFailure -ErrorRecord $operationError)) {
				if (-not $entry.PSObject.Properties['GroupName']) {
					$entry | Add-Member -NotePropertyName GroupName -NotePropertyValue $this.Name
				}
				$entries.Add($entry)
			}
			$operationError.Exception.Data['Fast1Archiving.CleanupFailures'] = $entries
			try {
				Write-LogMessage -Message "Archiving execution failed for group ($($this.Name)); inspect the primary error and cleanup contexts." `
					-Level Warning `
					-ErrorAction Stop
			}
			catch {
				Add-GenericSqlCleanupFailure -PrimaryError $operationError -CleanupError $_ `
					-Context @{ Action = 'LogFailure'; GroupName = $this.Name; ResourceRole = 'Log' } `
					-FailureKey 'Fast1Archiving.CleanupFailures'
			}
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{
					DestinationConnection = $this.DstSqlConn
					SourceConnection = $this.SrcSqlConn
					ConfigurationConnection = $this.ArcSqlConn
				}) `
			-PrimaryError $operationError `
			-Context @{ GroupName = $this.Name } `
			-FailureKey 'Fast1Archiving.CleanupFailures'
		}
	}

	hidden Initialize() {
		$sqlCmd = $null
		$sqlReader = $null
		$operationError = $null
		$sourceOptions = ''
		$destinationOptions = ''
		try {
			$this.ArcSqlConn = Get-ArchivingConnection -ConnectionString $this.ConnectionString -Role Configuration
			$this.ArcSqlConn.Open()
			$sqlCmd = Get-ArchivingCommand -Query 'dbo.stp_GetTableGroup' -Connection $this.ArcSqlConn
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$sqlCmd.Parameters.Add('@Name', [System.Data.SqlDbType]::NVarChar, 128).Value = $this.Name
			$sqlReader = $sqlCmd.ExecuteReader()
			if ($sqlReader.Read()) {
				$this.Id = $sqlReader['TableGroupId']
				$this.SrcServerName = $sqlReader['SrcServerName']
				$this.SrcDatabaseName = $sqlReader['SrcDatabaseName']
				$this.DstServerName = $sqlReader['DstServerName']
				$this.DstDatabaseName = $sqlReader['DstDatabaseName']
				$sourceOptions = [string]$sqlReader['SrcConnOptions']
				$destinationOptions = [string]$sqlReader['DstConnOptions']
				$this.DisableFK = $sqlReader['DisableFK']
			}
		}
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
		}
		if ($this.Id -eq 0) {
			return
		}
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($sourceOptions)
		$builder['Data Source'] = $this.SrcServerName
		$builder['Initial Catalog'] = $this.SrcDatabaseName
		$this.SrcSqlConn = Get-ArchivingConnection -ConnectionString $builder.ConnectionString -Role Source
		$this.SrcSqlConn.Open()
		# Compare server identities so two aliases of one instance remain valid.
		$configurationServer = Get-ArchivingServerIdentity -Connection $this.ArcSqlConn
		$sourceServer = Get-ArchivingServerIdentity -Connection $this.SrcSqlConn
		if ([string]::IsNullOrWhiteSpace($configurationServer) -or $configurationServer -ne $sourceServer) {
			throw 'Configuration and source databases must reside on the same SQL Server instance.'
		}
		$builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($destinationOptions)
		$builder['Data Source'] = $this.DstServerName
		$builder['Initial Catalog'] = $this.DstDatabaseName
		$this.DstSqlConn = Get-ArchivingConnection -ConnectionString $builder.ConnectionString -Role Destination
		$this.DstSqlConn.Open()
	}

	ReadSourceTables() {
		$sqlCmd = $null
		$sqlReader = $null
		$operationError = $null
		try {
			$sqlCmd = Get-ArchivingCommand -Query 'dbo.stp_GetSourceTable' -Connection $this.ArcSqlConn
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pTableGroupId = $sqlCmd.Parameters.Add('@TableGroupId', [System.Data.SqlDbType]::Int)
			$pTableGroupId.Value = $this.Id

			$sqlReader = $sqlCmd.ExecuteReader()
			while ($sqlReader.Read()) {
				$this.SourceTables.Add(
					(Get-ArchivingTable -Values @{
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
					})
				)
			}
		}
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
		}
	}

	Dispose() {
		Close-GenericSqlResource -Resources ([ordered]@{
				DestinationConnection = $this.DstSqlConn
				SourceConnection = $this.SrcSqlConn
				ConfigurationConnection = $this.ArcSqlConn
			}) `
			-Context @{ GroupName = $this.Name } `
			-FailureKey 'Fast1Archiving.CleanupFailures'
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
		$this.KeyMaxValue = [int](Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateKeyMaxValue' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
			} `
			-Scalar
		)
	}

	UpdateKeyCopyDate() {
		$confirmedDate = [datetime]::Now
		Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				KeyCopyDate = [GenericSqlParam]@{
					Value = $confirmedDate
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
		$this.KeyCopyDate = $confirmedDate
	}

	UpdateCompleteDate() {
		$confirmedDate = [datetime]::Now
		Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				CompleteDate = [GenericSqlParam]@{
					Value = $confirmedDate
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
		$this.CompleteDate = $confirmedDate
	}

	UpdateArchiveComplete() {
		$confirmedDate = [datetime]::Now
		Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastArchivedKey = [GenericSqlParam]@{
					Value = $this.LastArchivedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsArchived = [GenericSqlParam]@{
					Value = $this.RowsArchived
					Type  = [System.Data.SqlDbType]::Int
				}
				ArchiveCompleteDate = [GenericSqlParam]@{
					Value = $confirmedDate
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
		$this.ArchiveCompleteDate = $confirmedDate
	}

	UpdateArchiveState() {
		Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastArchivedKey = [GenericSqlParam]@{
					Value = $this.LastArchivedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsArchived = [GenericSqlParam]@{
					Value = $this.RowsArchived
					Type  = [System.Data.SqlDbType]::Int
				}
			}
	}

	UpdatePurgeComplete() {
		$confirmedDate = [datetime]::Now
		Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastPurgedKey = [GenericSqlParam]@{
					Value = $this.LastPurgedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsPurged = [GenericSqlParam]@{
					Value = $this.RowsPurged
					Type  = [System.Data.SqlDbType]::Int
				}
				PurgeCompleteDate = [GenericSqlParam]@{
					Value = $confirmedDate
					Type  = [System.Data.SqlDbType]::DateTime
				}
			}
		$this.PurgeCompleteDate = $confirmedDate
	}

	UpdatePurgeState() {
		Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_UpdateProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.Id
					Type  = [System.Data.SqlDbType]::Int
				}
				LastPurgedKey = [GenericSqlParam]@{
					Value = $this.LastPurgedKey
					Type  = [System.Data.SqlDbType]::Int
				}
				RowsPurged = [GenericSqlParam]@{
					Value = $this.RowsPurged
					Type  = [System.Data.SqlDbType]::Int
				}
			}
	}

	Create() {
		if ($this.Id -ne 0) {
			throw 'State.Id already has a value'
		}
		$this.Id = [int](Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_InsertProcessState' `
			-CommandType StoredProcedure `
			-Parameters @{
				SourceTableId = [GenericSqlParam]@{
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
		$newLastArchivedKey = [int](Invoke-GenericSqlQuery `
			-SqlConn $this.ArcSqlConn `
			-Query 'dbo.stp_FixLastArchivedKey' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
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
	hidden [ProcessState]$State
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
	hidden [object[]]$ConstraintObligations = @()

	Prepare() {
		if (-not $this.IsTableExistsInSource()) {
			throw "The source table [$($this.SchemaName)].[$($this.TableName)] doesn't exist"
		}
		$this.ReadSrcTableColumns()
		if ($this.SrcPkColumns.Count -eq 0) {
			throw 'An archiving source table must have a primary key.'
		}
		if ($this.KeyCopyBatchSize -le 0 -or $this.DataCopyBatchSize -le 0 -or $this.PurgeBatchSize -le 0) {
			throw 'Archiving batch sizes must be positive.'
		}
		if ($this.Archive) {
			if (-not $this.IsTableExistsInDestination()) {
				if (-not $this.IsTableSchemaExistsInDestination()) {
					$this.CreateDestinationTableSchema()
				}
				$this.CreateDestinationTable()
			}
			else {
				$this.ReadDstTableColumns()
				Compare-Column -SrcColumns $this.SrcColumns -DstColumns $this.DstColumns
				[void]$this.AddMissedColumns()
			}
		}
		$this.GetState()
		if (-not $this.State.IncompleteProcess) {
			$this.State.Create()
		}
		if (-not $this.State.IsPkCopied()) {
			$this.CreateSourceWorkingTable()
			$this.BulkCopySourcePK()
			$this.State.UpdateKeyMaxValue()
			$this.State.UpdateKeyCopyDate()
		}
		if ($this.State.IncompleteProcess -or $this.AlwaysRunCheck) {
			$this.CreateDestinationWorkingTable()
			if ($this.State.KeyMaxValue -ne 0) {
				$this.BulkCopyDestinationPK()
			}
			[void]$this.State.FixAndGetLastArchivedKey()
		}
		else {
			$this.ConfirmArchive(0, 0)
		}
	}

	hidden ConfirmArchive([int]$Position, [int]$Count) {
		$candidate = [ProcessState]@{
			Id = $this.State.Id
			ArcSqlConn = $this.Group.ArcSqlConn
			LastArchivedKey = $Position
			RowsArchived = $Count
		}
		$candidate.UpdateArchiveState()
		$this.State.LastArchivedKey = $Position
		$this.State.RowsArchived = $Count
	}

	hidden ConfirmPurge([int]$Position, [int]$Count) {
		$candidate = [ProcessState]@{
			Id = $this.State.Id
			ArcSqlConn = $this.Group.ArcSqlConn
			LastPurgedKey = $Position
			RowsPurged = $Count
		}
		$candidate.UpdatePurgeState()
		$this.State.LastPurgedKey = $Position
		$this.State.RowsPurged = $Count
	}

	ExecuteArchive() {
		$rowsThisRun = 0
		if ($this.State.ArchiveCompleteDate -eq [datetime]::MinValue) {
			while ($this.State.ArchiveProcessHasRowsForNextBatch()) {
				$this.State.RowsArchivedForBatch = 0
				$this.BulkCopyTable()
				$this.ConfirmArchive($this.State.LastArchivedKey + $this.DataCopyBatchSize, $this.State.RowsArchived + $this.State.RowsArchivedForBatch)
				$rowsThisRun += $this.State.RowsArchivedForBatch
				if ($this.State.RowsArchivedForBatch -gt 0) {
					Start-Sleep -Seconds $this.DelayIntervalInSeconds
				}
			}
			$this.State.UpdateArchiveComplete()
		}
		Write-LogMessage -Message "Archiving completed for [$($this.SchemaName)].[$($this.TableName)]. Rows archived (now): $rowsThisRun. Rows archived (state): $($this.State.RowsArchived)"
		if (-not $this.Purge) {
			$this.Complete()
		}
	}

	ExecutePurge() {
		$rowsThisRun = 0
		if ($this.State.PurgeCompleteDate -eq [datetime]::MinValue) {
			if (-not $this.State.IncompleteProcess) {
				$this.ConfirmPurge(0, 0)
			}
			$operationError = $null
			try {
				$this.DisableSourceConstraints()
				while ($this.State.PurgeProcessHasRowsForNextBatch()) {
					$this.State.RowsPurgedForBatch = 0
					$this.PurgeData()
					$this.ConfirmPurge($this.State.LastPurgedKey + $this.PurgeBatchSize, $this.State.RowsPurged + $this.State.RowsPurgedForBatch)
					$rowsThisRun += $this.State.RowsPurgedForBatch
					Start-Sleep -Seconds $this.DelayIntervalInSeconds
				}
			}
			catch {
				$operationError = $_
				throw
			}
			finally {
				$this.RestoreSourceConstraints($operationError)
			}
			$this.State.UpdatePurgeComplete()
		}
		Write-LogMessage -Message "Purging completed for [$($this.SchemaName)].[$($this.TableName)]. Rows purged (now): $rowsThisRun. Rows purged (state): $($this.State.RowsPurged)"
		$this.Complete()
	}

	hidden Complete() {
		$this.State.UpdateCompleteDate()
		$this.DropWorkingTables()
	}

	hidden DisableSourceConstraints() {
		if (-not $this.Group.DisableFK) {
			return
		}
		# Register the entire scope before any DDL, including uncertain disables.
		$this.ConstraintObligations = @($this.ReadSourceConstraints())
		foreach ($constraint in $this.ConstraintObligations) {
			Invoke-ArchivingConstraintAction -Connection $this.Group.SrcSqlConn -Constraint $constraint -Disable $true
		}
	}

	hidden RestoreSourceConstraints([System.Management.Automation.ErrorRecord]$PrimaryError) {
		$failure = $PrimaryError
		foreach ($constraint in $this.ConstraintObligations) {
			try {
				Invoke-ArchivingConstraintAction -Connection $this.Group.SrcSqlConn -Constraint $constraint -Disable $false
			}
			catch {
				if ($null -eq $failure) {
					$failure = $_
				}
				Add-GenericSqlCleanupFailure -PrimaryError $failure -CleanupError $_ -FailureKey 'Fast1Archiving.CleanupFailures' -Context @{
					Action = 'RestoreConstraint'
					GroupName = $this.Group.Name
					SourceTable = "$($this.SchemaName).$($this.TableName)"
					ProcessStateId = $this.State.Id
					DatabaseName = $constraint.DatabaseName
					SchemaName = $constraint.SchemaName
					TableName = $constraint.TableName
					ConstraintName = $constraint.ConstraintName
				}
			}
		}
		$this.ConstraintObligations = @()
		if ($null -eq $PrimaryError -and $null -ne $failure) {
			throw $failure
		}
	}

	hidden [object[]]ReadSourceConstraints() {
		$query = @'
select distinct db_name() DatabaseName, s.name SchemaName, t.name TableName, fk.name ConstraintName
from sys.foreign_keys fk
join sys.tables t on t.object_id = fk.parent_object_id
join sys.schemas s on s.schema_id = t.schema_id
join sys.tables r on r.object_id = fk.referenced_object_id
join sys.schemas rs on rs.schema_id = r.schema_id
where rs.name = @SchemaName and r.name = @TableName
order by s.name, t.name, fk.name
'@
		$sqlCmd = $null
		$sqlReader = $null
		$operationError = $null
		$constraints = [List[object]]::new()
		try {
			$sqlCmd = Get-ArchivingCommand -Query $query -Connection $this.Group.SrcSqlConn
			$sqlCmd.Parameters.Add('@SchemaName', [System.Data.SqlDbType]::NVarChar, 128).Value = $this.SchemaName
			$sqlCmd.Parameters.Add('@TableName', [System.Data.SqlDbType]::NVarChar, 128).Value = $this.TableName
			$sqlReader = $sqlCmd.ExecuteReader()
			while ($sqlReader.Read()) {
				$constraints.Add([PSCustomObject]@{
					DatabaseName = $sqlReader['DatabaseName']
					SchemaName = $sqlReader['SchemaName']
					TableName = $sqlReader['TableName']
					ConstraintName = $sqlReader['ConstraintName']
				})
			}
		}
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-Context @{ GroupName = $this.Group.Name; SourceTable = "$($this.SchemaName).$($this.TableName)" } `
				-FailureKey 'Fast1Archiving.CleanupFailures'
		}
		return $constraints.ToArray()
	}

	GetState() {
		$sqlCmd = $null
		$sqlReader = $null
		$operationError = $null
		try {
			$this.State = [ProcessState]@{
				SourceTableId = $this.Id
				ArcSqlConn = $this.Group.ArcSqlConn
				IncompleteProcess = $false
			}

			$sqlCmd = Get-ArchivingCommand -Query 'dbo.stp_GetIncompleteProcessState' -Connection $this.Group.ArcSqlConn
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
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
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
		return [bool](Invoke-GenericSqlQuery `
			-SqlConn $sqlConnection `
			-Query $query `
			-Parameters @{
				SchemaName = [GenericSqlParam]@{
					Value = $schemaName
					Type  = [System.Data.SqlDbType]::NVarChar
					Size  = 128
				}
				TableName = [GenericSqlParam]@{
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
		return [bool](Invoke-GenericSqlQuery `
			-SqlConn $sqlConnection `
			-Query $query `
			-Parameters @{
				SchemaName = [GenericSqlParam]@{
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
		$col += if ($c.Nullable) {
			' null'
		}
		else {
			' not null'
		}
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
select	COLUMN_NAME [Name], DATA_TYPE SqlType, coalesce(CHARACTER_MAXIMUM_LENGTH, 0) SqlSize,
		coalesce(NUMERIC_PRECISION, 0) SqlPrecision, coalesce(NUMERIC_SCALE, DATETIME_PRECISION, 0) SqlScale,
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
		$operationError = $null
		try {
			$sqlCmd = Get-ArchivingCommand -Query $query -Connection $sqlConnection
			$sqlCmd.Parameters.Add("@SchemaName", [System.Data.SqlDbType]::NVarChar, 128).Value = $schemaName
			$sqlCmd.Parameters.Add("@TableName", [System.Data.SqlDbType]::NVarChar, 128).Value = $tableName
			$sqlReader = $sqlCmd.ExecuteReader()
			$columns = [Dictionary[string, TableColumn]]::new([System.StringComparer]::OrdinalIgnoreCase)

			while ($sqlReader.Read()) {
				$columns[$sqlReader['Name']] = ([TableColumn]@{
					Name = $sqlReader['Name']
					DataType = $sqlReader['DataType']
					SqlType = $sqlReader['SqlType']
					SqlSize = $sqlReader['SqlSize']
					SqlPrecision = $sqlReader['SqlPrecision']
					SqlScale = $sqlReader['SqlScale']
					Collation = if ($sqlReader['Collation'] -isnot [System.DBNull]) {
						$sqlReader['Collation']
					}
					else {
						$null
					}
					Computed = $sqlReader['Computed']
					Nullable = $sqlReader['Nullable']
				})
			}
			return $columns
		}
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
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
		$operationError = $null
		try {
			$sqlCmd = Get-ArchivingCommand -Query $query -Connection $sqlConnection
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
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
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
		$operationError = $null
		try {
			$sqlCmd = Get-ArchivingCommand -Query $query -Connection $sqlConnection
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
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
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

		Invoke-GenericSqlQuery `
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

		Invoke-GenericSqlQuery `
			-SqlConn $this.Group.DstSqlConn `
			-Query $query.ToString()
	}

	CreateDestinationTableSchema() {
		$query = "create schema [$($this.SchemaName)]"
		Invoke-GenericSqlQuery `
			-SqlConn $this.Group.DstSqlConn `
			-Query $query.ToString()
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

		Invoke-GenericSqlQuery `
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

		Invoke-GenericSqlQuery `
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

		Invoke-GenericSqlQuery `
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
		$operationError = $null
		try {
			# source
			$sqlCmd = Get-ArchivingCommand -Query $this.KeyQuery -Connection $this.Group.SrcSqlConn
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$bulkCopy = Get-ArchivingBulkCopy -Connection $this.Group.ArcSqlConn

			$bulkCopy.DestinationTableName = $this.SrcWorkingTableName
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.KeyCopyBatchSize
			foreach ($c in $this.SrcPkColumns) {
				[void]$bulkCopy.ColumnMappings.Add([Microsoft.Data.SqlClient.SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
		}
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ BulkCopy = $bulkCopy; Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
		}
	}

	BulkCopyDestinationPK() {
		$keys = @($this.SrcPkColumns | Sort-Object Id)
		$pageSize = [Math]::Min($this.KeyCopyBatchSize, [int][Math]::Floor(2000 / $keys.Count))
		if ($pageSize -lt 1) {
			throw 'The captured primary key cannot fit in a reconciliation page.'
		}
		$working = ConvertTo-ArchivingIdentifier $this.SrcWorkingTableName
		$position = ConvertTo-ArchivingIdentifier $this.WorkingTableKeyName
		$columnNames = @($keys | ForEach-Object { ConvertTo-ArchivingIdentifier $_.Name })
		$columnsSql = $columnNames -join ', '
		$schema = ConvertTo-ArchivingIdentifier $this.SchemaName
		$tableNameSql = ConvertTo-ArchivingIdentifier $this.TableName
		$after = 0
		while ($true) {
			$page = [List[object]]::new()
			$sqlCmd = $null
			$sqlReader = $null
			$operationError = $null
			try {
				$sqlCmd = Get-ArchivingCommand -Query "select top (@PageSize) $position, $columnsSql from dbo.$working where $position > @After order by $position" -Connection $this.Group.ArcSqlConn
				$sqlCmd.Parameters.Add('@PageSize', [System.Data.SqlDbType]::Int).Value = $pageSize
				$sqlCmd.Parameters.Add('@After', [System.Data.SqlDbType]::Int).Value = $after
				$sqlReader = $sqlCmd.ExecuteReader()
				while ($sqlReader.Read()) {
					$values = [object[]]::new($keys.Count)
					for ($column = 0; $column -lt $keys.Count; $column++) {
						$values[$column] = $sqlReader.GetValue($column + 1)
					}
					$page.Add($values)
					$after = $sqlReader.GetInt32(0)
				}
			}
			catch {
				$operationError = $_
				throw
			}
			finally {
				# Never reuse the configuration connection with its reader still open.
				Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) `
					-PrimaryError $operationError `
					-FailureKey 'Fast1Archiving.CleanupFailures'
			}
			if ($page.Count -eq 0) {
				break
			}
			$sqlCmd = $null
			$sqlReader = $null
			$bulkCopy = $null
			$operationError = $null
			try {
				$sqlCmd = Get-ArchivingCommand -Query '' -Connection $this.Group.DstSqlConn
				$predicates = [List[string]]::new()
				for ($row = 0; $row -lt $page.Count; $row++) {
					$parts = [List[string]]::new()
					for ($column = 0; $column -lt $keys.Count; $column++) {
						$name = "@k$($row)_$column"
						$metadata = $this.SrcColumns[$keys[$column].Name]
						$sqlType = $metadata.SqlType
						if ($sqlType -eq 'numeric') {
							$sqlType = 'decimal'
						}
						elseif ($sqlType -eq 'sql_variant') {
							$sqlType = 'variant'
						}
						$parameter = $sqlCmd.Parameters.Add($name, [System.Data.SqlDbType][System.Enum]::Parse([System.Data.SqlDbType], $sqlType, $true))
						$parameter.Size = $metadata.SqlSize
						$parameter.Precision = $metadata.SqlPrecision
						$parameter.Scale = $metadata.SqlScale
						$parameter.Value = $page[$row][$column]
						$parts.Add($columnNames[$column] + ' = ' + $name)
					}
					$predicates.Add('(' + ($parts -join ' and ') + ')')
				}
				$sqlCmd.CommandText = "select $columnsSql from $schema.$tableNameSql where " + ($predicates -join ' or ')
				$sqlReader = $sqlCmd.ExecuteReader()
				$bulkCopy = Get-ArchivingBulkCopy -Connection $this.Group.ArcSqlConn
				$bulkCopy.DestinationTableName = 'dbo.' + (ConvertTo-ArchivingIdentifier $this.DstWorkingTableName)
				$bulkCopy.EnableStreaming = $true
				$bulkCopy.BatchSize = $this.KeyCopyBatchSize
				foreach ($key in $keys) {
					[void]$bulkCopy.ColumnMappings.Add($key.Name, $key.Name)
				}
				$bulkCopy.WriteToServer($sqlReader)
			}
			catch {
				$operationError = $_
				throw
			}
			finally {
				Close-GenericSqlResource -Resources ([ordered]@{ BulkCopy = $bulkCopy; Reader = $sqlReader; Command = $sqlCmd }) `
					-PrimaryError $operationError `
					-FailureKey 'Fast1Archiving.CleanupFailures'
			}
		}
	}

	BulkCopyTable() {
		$this.State.RowsArchivedForBatch = 0
		$sqlCmd = $null
		$sqlReader = $null
		$bulkCopy = $null
		$operationError = $null
		try {
			# source
			$sqlCmd = Get-ArchivingCommand -Query 'dbo.stp_GetBulkCopyData' -Connection $this.Group.ArcSqlConn
			$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
			$pProcessStateId = $sqlCmd.Parameters.Add('@ProcessStateId', [System.Data.SqlDbType]::Int)
			$pProcessStateId.Value = $this.State.Id
			$sqlReader = $sqlCmd.ExecuteReader()

			if (-not $sqlReader.HasRows) {
				return
			}

			# destination
			$options = [Microsoft.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity -bor [Microsoft.Data.SqlClient.SqlBulkCopyOptions]::KeepNulls
			$bulkCopy = Get-ArchivingBulkCopy -Connection $this.Group.DstSqlConn -Options $options

			$bulkCopy.DestinationTableName = "[$($this.SchemaName)].[$($this.TableName)]"
			$bulkCopy.EnableStreaming = $true
			$bulkCopy.BatchSize = $this.DataCopyBatchSize

			foreach ($c in $this.SrcColumns.Values.Where({ -not $_.Computed })) {
				[void]$bulkCopy.ColumnMappings.Add([Microsoft.Data.SqlClient.SqlBulkCopyColumnMapping]::new($c.Name, $c.Name))
			}

			$bulkCopy.WriteToServer($sqlReader)
			$this.State.RowsArchivedForBatch = $bulkCopy.RowsCopied
		}
		catch {
			$operationError = $_
			throw
		}
		finally {
			Close-GenericSqlResource -Resources ([ordered]@{ BulkCopy = $bulkCopy; Reader = $sqlReader; Command = $sqlCmd }) `
				-PrimaryError $operationError `
				-FailureKey 'Fast1Archiving.CleanupFailures'
		}
	}

	PurgeData() {
		$this.State.RowsPurgedForBatch = 0
		$this.State.RowsPurgedForBatch = [int](Invoke-GenericSqlQuery `
			-SqlConn $this.Group.ArcSqlConn `
			-Query 'dbo.stp_PurgeData' `
			-CommandType StoredProcedure `
			-Parameters @{
				ProcessStateId = [GenericSqlParam]@{
					Value = $this.State.Id
					Type  = [System.Data.SqlDbType]::Int
				}
			} `
			-Scalar
		)
	}
}

