using module ./ArchivingModel.psm1

function Invoke-ArchivingProcess {
	Param (
		[parameter(Mandatory)]
		[string]$ConnStr,

		[parameter(Mandatory)]
		[string]$GroupName,

		[string]$LogFile
	)

	Set-StrictMode -Version Latest

	$group = $null
	try { 
		$group = [TableGroup]::new($ConnStr, $GroupName)
		if ($group.Id -eq 0) {
			throw "Specified table group ($GroupName) not found"
		}
		Write-LogMessage -Message "Archive group ($GroupName) found" -LogFile $LogFile

		$group.ReadSourceTables()

		if ($group.SourceTables.Count -eq 0) {
			Write-LogMessage -Message "No tables found for the specified table group ($GroupName)" -LogFile $LogFile
			return
		}
		Write-LogMessage -Message "$($group.SourceTables.Count) archive/purge table(s) found" -LogFile $LogFile

		$b = $false
		foreach ($table in $group.SourceTables) {
			if (-not $table.Archive -and -not $table.Purge) {
				Write-LogMessage -Message "Skipping table [$($table.SchemaName)].[$($table.TableName)] since it's not enabled for archiving and purging" `
					-LogFile $LogFile
				continue
			}
			if (-not ($table.IsTableExistsInSource())) {
				throw "The source table [$($table.SchemaName)].[$($table.TableName)] doesn't exist"
			}
			$table.ReadSrcTableColumns()
			Write-LogMessage -Message "Columns info collected for source table [$($table.SchemaName)].[$($table.TableName)]" `
				-LogFile $LogFile

			if ($table.Archive) {
				if (-not $table.IsTableExistsInDestination()) {
					if (-not $table.IsTableSchemaExistsInDestination()) {
						Write-LogMessage -Message "The destination schema [$($table.SchemaName)] doesn't exist. Creating..." `
							-LogFile $LogFile
						$table.CreateDestinationTableSchema()
						Write-LogMessage -Message "The destination schema [$($table.SchemaName)] created" `
							-LogFile $LogFile
					}
					Write-LogMessage -Message "The destination table [$($table.SchemaName)].[$($table.TableName)] doesn't exist. Creating..." `
						-LogFile $LogFile
					$table.CreateDestinationTable()
					Write-LogMessage -Message "The destination table [$($table.SchemaName)].[$($table.TableName)] created" -LogFile $LogFile
				}
				else {
					$table.ReadDstTableColumns()
					Write-LogMessage -Message "Columns info collected for destination table [$($table.SchemaName)].[$($table.TableName)]" `
						-LogFile $LogFile

					Compare-Column -SrcColumns $table.SrcColumns -DstColumns $table.DstColumns -LogFile $LogFile

					if ($table.AddMissedColumns()) {
						Write-LogMessage -Message "Missing column(s) added to the [$($table.SchemaName)].[$($table.TableName)] table" `
							-LogFile $LogFile
					}

					Write-LogMessage -Message "Schema comparision completed for the [$($table.SchemaName)].[$($table.TableName)] table" `
						-LogFile $LogFile
				}
			}

			$table.GetState()

			if ($table.State.IncompleteProcess) {
				Write-LogMessage -Message "Incomplete process found for the table [$($table.SchemaName)].[$($table.TableName)]" `
					 -LogFile $LogFile
			}
			else {
				$table.State.Create()
			}

			if (-not $table.State.IsPkCopied()) {
				# Create a working table
				$table.CreateSourceWorkingTable()
				Write-LogMessage -Message "Working table created for [$($table.SchemaName)].[$($table.TableName)]" `
					-LogFile $LogFile

				# Populate PK values from source and update KeyCopyDate
				Write-LogMessage -Message "PK copy started for the table [$($table.SchemaName)].[$($table.TableName)]" `
					-LogFile $LogFile
				$table.BulkCopySourcePK()
				Write-LogMessage -Message "PK values copied for the table [$($table.SchemaName)].[$($table.TableName)]" `
					-LogFile $LogFile

				$table.State.UpdateKeyMaxValue()
				$table.State.UpdateKeyCopyDate()
			}

			if ($table.State.IncompleteProcess -or $table.AlwaysRunCheck) {
				$table.CreateDestinationWorkingTable()
				# Only copy if there is a data in the source table
				if ($table.State.KeyMaxValue -ne 0) {
					$table.BulkCopyDestinationPK()
				}
				if ($table.State.FixAndGetLastArchivedKey()) {
					Write-LogMessage -Message "LastArchivedKey fixed for the table [$($table.SchemaName)].[$($table.TableName)]" `
						-LogFile $LogFile
				}
			}
			else {
				$table.State.LastArchivedKey = 0
				$table.State.RowsArchived = 0
				$table.State.UpdateArchiveState()
			}

			if ($table.Archive) {
				Write-LogMessage -Message "Archiving started for the table [$($table.SchemaName)].[$($table.TableName)]" `
					-LogFile $LogFile
				
				$rowsArchivedPerRun = 0
				while ($table.State.ArchiveProcessHasRowsForNextBatch()) {
					$table.BulkCopyTable()

					$table.State.LastArchivedKey += $table.DataCopyBatchSize
					$table.State.RowsArchived += $table.State.RowsArchivedForBatch
					$rowsArchivedPerRun += $table.State.RowsArchivedForBatch
					$table.State.UpdateArchiveState()
					if ($table.State.RowsArchivedForBatch -gt 0) {
						Start-Sleep -Seconds $table.DelayIntervalInSeconds
					}
				}
				$table.State.UpdateArchiveComplete()
				if ($table.State.RowsArchived -gt 0) {
					$message = "Archiving completed for the table [$($table.SchemaName)].[$($table.TableName)]. " +
						"Rows archived (now): $rowsArchivedPerRun. Rows archived (state): $($table.State.RowsArchived)"
					Write-LogMessage -Message $message -LogFile $LogFile
				}
				else {
					Write-LogMessage -Message "There was no data to archive for the table [$($table.SchemaName)].[$($table.TableName)]" `
						-LogFile $LogFile
				}

				if (-not $table.Purge) {
					$table.State.UpdateCompleteDate()
					$table.DropWorkingTables()
				}
				$b = $true
			}
		}
		if ($b) {
			Write-LogMessage -Message "Archiving process completed for the group ($($group.Name))" -LogFile $LogFile
		}

		# For each table in a group according to PurgeOrder
		$b = $false
		foreach ($table in $group.SourceTables.Where({ $_.Purge }) | Sort-Object -Property PurgeOrder) { 
			if (-not $table.State.IncompleteProcess) {
				$table.State.LastPurgedKey = 0
				$table.State.RowsPurged = 0
				$table.State.UpdatePurgeState()
			}

			Write-LogMessage -Message "Purging started for the table [$($table.SchemaName)].[$($table.TableName)]" `
				-LogFile $LogFile

			$rowsPurgedPerRun = 0
			$table.DisableEnableFK($true)
			while ($table.State.PurgeProcessHasRowsForNextBatch()) {
				$table.PurgeData()
				$table.State.LastPurgedKey += $table.PurgeBatchSize
				$table.State.RowsPurged += $table.State.RowsPurgedForBatch
				$rowsPurgedPerRun += $table.State.RowsPurgedForBatch
				$table.State.UpdatePurgeState()
				Start-Sleep -s $table.DelayIntervalInSeconds
			}
			$table.DisableEnableFK($false)
			$table.State.UpdatePurgeComplete()
			if ($table.State.RowsPurged -gt 0) {
				$message = "Purging completed for the table [$($table.SchemaName)].[$($table.TableName)]. " +
					"Rows purged (now): $rowsPurgedPerRun. Rows purged (state): $($table.State.RowsPurged)"
				Write-LogMessage -Message $message -LogFile $LogFile
			}
			else {
				Write-LogMessage -Message "There was no data to purge for the table [$($table.SchemaName)].[$($table.TableName)]" `
					-LogFile $LogFile
			}

			$table.State.UpdateCompleteDate()
			$table.DropWorkingTables()
		}
		if ($b) {
			Write-LogMessage -Message "Purging completed for the group ($($group.Name))" -LogFile $LogFile
		}
	}
	catch {
		Write-LogMessage -Message $_.Exception.ToString() -LogFile $LogFile `
			-Level Error
		throw
	}
	finally {
		if ($null -ne $group) {
			$group.Dispose()
		}
	}
}
