using module ../private/shared/GenericSqlParam.psm1

BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '../Fast1data.SqlServer.psd1') -Force
	InModuleScope ArchivingModel {
		function script:Get-ControlledReader {
			param ([object[]]$Rows, [string]$Role)
			$data = [System.Data.DataTable]::new()
			if ($Rows.Count -gt 0) {
				foreach ($name in $Rows[0].Keys) {
					[void]$data.Columns.Add($name, [object])
				}
				foreach ($values in $Rows) {
					$row = $data.NewRow()
					foreach ($name in $values.Keys) {
						$row[$name] = $values[$name]
					}
					$data.Rows.Add($row)
				}
			}
			$reader = $data.CreateDataReader()
			Add-Member -InputObject $reader -NotePropertyName Harness -NotePropertyValue $script:h
			Add-Member -InputObject $reader -NotePropertyName Role -NotePropertyValue $Role
			Add-Member -InputObject $reader -MemberType ScriptMethod -Name Dispose -Force -Value {
				$this.Harness.Record("release reader $($this.Role)")
				$this.psbase.Dispose()
			}
			return ,$reader
		}
	}
}

Describe 'Owned archiving execution without SQL' {
	It 'constructs an inert single-use owner without allocating connections' {
		InModuleScope ArchivingModel {
			$group = [TableGroup]::new('not a connection string', 'controlled')
			$group.ArcSqlConn | Should -BeNullOrEmpty
			$group.SrcSqlConn | Should -BeNullOrEmpty
			$group.DstSqlConn | Should -BeNullOrEmpty
		}
	}

	It 'keeps the caller limited to construction and one execution request' {
		$caller = Get-Content (Join-Path $PSScriptRoot '../private/archiving/Invoke-ArchivingProcess.ps1') -Raw
		$caller | Should -Match '\.Execute\(\$LogFile\)'
		$caller | Should -Not -Match '\.State|\.Dispose\(|DisableEnableFK|UpdateArchive|UpdatePurge|foreach|while'
	}

	It 'retains the public parameter and export contract' {
		$command = Get-Command Invoke-Fast1Archiving
		foreach ($name in @('ConnStr', 'GroupName', 'LogFile')) {
			$command.Parameters[$name].ParameterType | Should -Be ([string])
		}
		foreach ($name in @('ConnStr', 'GroupName')) {
			$attributes = $command.Parameters[$name].Attributes |
				Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

			$attributes.Mandatory | Should -Contain $true
		}
		@(Get-Command -Module Fast1data.SqlServer).Count | Should -Be 3
	}
}

Describe 'Execution lifetime, transitions and cleanup through the same request' {
	BeforeEach {
		InModuleScope ArchivingModel {
			$script:h = [pscustomobject]@{
				Events = [System.Collections.Generic.List[string]]::new()
				Failures = @{}
				CommitThenThrow = ''
				Found = $true
				Tables = @(@{ Id = 11; Archive = $true; Purge = $true; PurgeOrder = 1 })
				Persisted = @{}
				Instances = [System.Collections.Generic.List[object]]::new()
				Constraints = @()
				RealCopy = $false
			}
			$script:h | Add-Member -MemberType ScriptMethod -Name Record -Value {
				param ([string]$RecordedEvent)
				$this.Events.Add($RecordedEvent)
				if ($this.Failures.ContainsKey($RecordedEvent)) {
					throw $this.Failures[$RecordedEvent]
				}
			}
			Mock Get-ArchivingConnection {
				param ($ConnectionString, $Role)
				$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($ConnectionString)
				$connection | Add-Member -NotePropertyName Harness -NotePropertyValue $script:h
				$connection | Add-Member -NotePropertyName Role -NotePropertyValue $Role
				$connection | Add-Member -MemberType ScriptMethod -Name Open -Force -Value {
					$this.Harness.Record("open $($this.Role)")
				}
				$connection | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Harness.Record("release $($this.Role)")
					$this.psbase.Dispose()
				}
				$script:h.Record("allocate $Role")
				$connection
			}
			Mock Get-ArchivingServerIdentity { 'controlled-instance' }
			Mock Get-ArchivingCommand {
				param ($Query, $Connection)
				$rows = @()
				if ($Query -eq 'dbo.stp_GetTableGroup') {
					if ($script:h.Found) {
						$rows = @(@{ TableGroupId = 1; SrcServerName = 'controlled'; SrcDatabaseName = 'source'; SrcConnOptions = ''; DstServerName = 'controlled'; DstDatabaseName = 'destination'; DstConnOptions = ''; DisableFK = ($script:h.Constraints.Count -gt 0) })
					}
				}
				elseif ($Query -eq 'dbo.stp_GetSourceTable') {
					$rows = @(
						foreach ($table in $script:h.Tables) {
							@{ SourceTableId = $table.Id; SchemaName = 'dbo'; TableName = "t$($table.Id)"; DataCopyBatchSize = 2; KeyCopyBatchSize = 3; PurgeBatchSize = 2; KeyQuery = 'never executed'; Archive = $table.Archive; Purge = $table.Purge; PurgeOrder = $table.PurgeOrder; DelayInterval = '00:00:01'; AlwaysRunCheck = $false; SrcWorkingTableName = "w$($table.Id)"; DstWorkingTableName = "d$($table.Id)"; WorkingTableKeyName = 'position'; WorkingTableFlagName = 'skip' }
						}
					)
				}
				elseif ($Query -eq 'dbo.stp_GetBulkCopyData') {
					$rows = @(@{ Id = 1 }, @{ Id = 2 })
				}
				else {
					throw "Unexpected SQL in controlled suite: $Query"
				}
				$command = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $Connection)
				$command | Add-Member -NotePropertyName Harness -NotePropertyValue $script:h
				$command | Add-Member -NotePropertyName TestReader -NotePropertyValue (Get-ControlledReader -Rows $rows -Role $Query)
				$command | Add-Member -MemberType ScriptMethod -Name ExecuteReader -Force -Value {
					$this.Harness.Record("read $($this.CommandText)")
					return ,$this.TestReader
				}
				$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Harness.Record("release command $($this.CommandText)")
					$this.psbase.Dispose()
				}
				$command
			}
			Mock Get-ArchivingTable {
				param ($Values)
				$table = [Table]$Values
				$table | Add-Member -NotePropertyName Harness -NotePropertyValue $script:h
				$table | Add-Member -MemberType ScriptMethod -Name IsTableExistsInSource -Force -Value { $true }
				$table | Add-Member -MemberType ScriptMethod -Name IsTableExistsInDestination -Force -Value { $true }
				$table | Add-Member -MemberType ScriptMethod -Name ReadSrcTableColumns -Force -Value {
					$this.Harness.Record("prepare $($this.Id)")
					$this.SrcPkColumns = [System.Collections.Generic.List[IndexColumn]]::new()
					$this.SrcPkColumns.Add([IndexColumn]@{ Id = 1; Name = 'Id'; Order = 'asc' })
					$this.SrcColumns = [System.Collections.Generic.Dictionary[string, TableColumn]]::new()
					$this.SrcColumns.Add('Id', [TableColumn]@{ Name = 'Id'; DataType = 'int' })
				}
				$table | Add-Member -MemberType ScriptMethod -Name ReadDstTableColumns -Force -Value { $this.DstColumns = $this.SrcColumns }
				$table | Add-Member -MemberType ScriptMethod -Name AddMissedColumns -Force -Value { $false }
				$table | Add-Member -MemberType ScriptMethod -Name GetState -Force -Value {
					if (-not $this.Harness.Persisted.ContainsKey($this.Id)) {
						$this.Harness.Persisted[$this.Id] = @{ Id = $this.Id + 100; SourceTableId = $this.Id; KeyMaxValue = 5; KeyCopyDate = [datetime]::Now; LastArchivedKey = 0; RowsArchived = 0; LastPurgedKey = 0; RowsPurged = 0; IncompleteProcess = $true }
					}
					$this.State = [ProcessState]($this.Harness.Persisted[$this.Id] + @{ ArcSqlConn = $this.Group.ArcSqlConn })
					$this.Harness.Record("load $($this.Id) $($this.State.LastArchivedKey)")
				}
				$table | Add-Member -MemberType ScriptMethod -Name CreateDestinationWorkingTable -Force -Value { $this.Harness.Record("snapshot create $($this.Id)") }
				$table | Add-Member -MemberType ScriptMethod -Name BulkCopyDestinationPK -Force -Value { $this.Harness.Record("snapshot copy $($this.Id)") }
				$table | Add-Member -MemberType ScriptMethod -Name BulkCopyTable -Force -Value {
					$this.Harness.Record("copy reset $($this.State.RowsArchivedForBatch)")
					$this.State.RowsArchivedForBatch = 999
					$this.Harness.Record("copy $($this.Id) $($this.State.LastArchivedKey)")
					$this.State.RowsArchivedForBatch = [Math]::Min(2, 5 - $this.State.LastArchivedKey)
				}
				$table | Add-Member -MemberType ScriptMethod -Name PurgeData -Force -Value {
					$this.Harness.Record("delete $($this.Id) $($this.State.LastPurgedKey)")
					$this.State.RowsPurgedForBatch = [Math]::Min(2, 5 - $this.State.LastPurgedKey)
				}
				$table | Add-Member -MemberType ScriptMethod -Name ReadSourceConstraints -Force -Value { $this.Harness.Constraints }
				$table | Add-Member -MemberType ScriptMethod -Name DropWorkingTables -Force -Value { $this.Harness.Record("drop $($this.Id)") }
				$script:h.Instances.Add($table)
				if ($script:h.RealCopy) {
					$table.PSObject.Methods.Remove('BulkCopyTable')
				}
				$table
			}
			Mock Get-ArchivingBulkCopy {
				param ($Connection, [Microsoft.Data.SqlClient.SqlBulkCopyOptions]$Options = 0)
				$bulk = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($Connection, $Options, $null)
				$bulk | Add-Member -NotePropertyName Harness -NotePropertyValue $script:h
				$bulk | Add-Member -MemberType ScriptMethod -Name WriteToServer -Force -Value {
					param ($Reader)
					$null = $Reader
					$this.Harness.Record('bulk write')
				}
				$bulk | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Harness.Record('release bulk')
					$this.psbase.Dispose()
				}
				$bulk
			}
			Mock Invoke-GenericSqlQuery {
				param ($Query, $Parameters)
				$id = [int]$Parameters.ProcessStateId.Value - 100
				$state = $script:h.Persisted[$id]
				if ($Query -eq 'dbo.stp_FixLastArchivedKey') {
					$script:h.Record("reconcile $id")
					return $state.LastArchivedKey
				}
				if ($Query -ne 'dbo.stp_UpdateProcessState') {
					throw "Unexpected checkpoint: $Query"
				}
				foreach ($name in $Parameters.Keys | Where-Object { $_ -ne 'ProcessStateId' } | Sort-Object) {
					$checkpointEvent = "write $id $name"
					if ($script:h.CommitThenThrow -eq $checkpointEvent) {
						$state[$name] = $Parameters[$name].Value
					}
					$script:h.Record($checkpointEvent)
				}
				foreach ($name in $Parameters.Keys | Where-Object { $_ -ne 'ProcessStateId' }) {
					$state[$name] = $Parameters[$name].Value
				}
			}
			Mock Invoke-ArchivingConstraintAction {
				param ($Constraint, $Disable)
				$script:h.Record("constraint $($Constraint.ConstraintName) $Disable")
			}
			Mock Start-Sleep { $script:h.Record("delay $Seconds") }
			Mock Write-LogMessage { $script:h.Record("log $Level") }
		}
	}

	It 'releases every allocated connection when <Role> opening fails' -ForEach @(
		@{ Role = 'Source'; Released = 'release Source,release Configuration' }
		@{ Role = 'Destination'; Released = 'release Destination,release Source,release Configuration' }
	) {
		InModuleScope ArchivingModel -Parameters @{ Role = $Role; Released = $Released } {
			$script:h.Failures["open $Role"] = [InvalidOperationException]::new('opening failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*opening failed*'
			@($script:h.Events | Where-Object { $_ -match '^release (Source|Destination|Configuration)$' }) -join ',' | Should -Be $Released
		}
	}

	It 'owns successful batches, resets activity, confirms effects then completion and releases connections' {
		InModuleScope ArchivingModel {
			@(Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled').Count | Should -Be 0
			$script:h.Persisted[11].RowsArchived | Should -Be 5
			$script:h.Persisted[11].RowsPurged | Should -Be 5
			@($script:h.Events | Where-Object { $_ -eq 'copy reset 0' }).Count | Should -Be 3
			$script:h.Events.IndexOf('copy 11 0') | Should -BeLessThan $script:h.Events.IndexOf('write 11 LastArchivedKey')
			$script:h.Events.IndexOf('write 11 CompleteDate') | Should -BeLessThan $script:h.Events.IndexOf('drop 11')
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'rejects candidate progress on <Fault> failure and stops later work' -ForEach @(
		@{ Fault = 'copy 11 0' }
		@{ Fault = 'write 11 LastArchivedKey' }
		@{ Fault = 'write 11 ArchiveCompleteDate' }
		@{ Fault = 'delete 11 0' }
		@{ Fault = 'write 11 LastPurgedKey' }
		@{ Fault = 'write 11 PurgeCompleteDate' }
		@{ Fault = 'write 11 CompleteDate' }
	) {
		InModuleScope ArchivingModel -Parameters @{ Fault = $Fault } {
			$script:h.Failures[$Fault] = [InvalidOperationException]::new('controlled fault')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*controlled fault*'
			$script:h.Events | Should -Not -Contain 'drop 11'
			$script:h.Persisted[11].ContainsKey('CompleteDate') | Should -BeFalse
			if ($Fault -in @('copy 11 0', 'write 11 LastArchivedKey')) {
				$script:h.Instances[0].State.LastArchivedKey | Should -Be 0
				$script:h.Events | Should -Not -Contain 'delete 11 0'
			}
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'reloads a committed write after a lost response using a fresh owner' {
		InModuleScope ArchivingModel {
			$script:h.CommitThenThrow = 'write 11 ArchiveCompleteDate'
			$script:h.Failures[$script:h.CommitThenThrow] = [InvalidOperationException]::new('lost response')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*lost response*'
			$script:h.Failures.Clear()
			$script:h.Events.Clear()
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events | Should -Contain 'load 11 6'
			$script:h.Events | Should -Not -Contain 'copy 11 0'
		}
	}

	It 'preserves the operation error and reports all independent cleanup failures in encounter order' {
		InModuleScope ArchivingModel {
			$script:h.Failures['open Destination'] = [InvalidOperationException]::new('original opening failure')
			$script:h.Failures['release Destination'] = [InvalidOperationException]::new('Password=secret')
			$script:h.Failures['release Source'] = [InvalidOperationException]::new('sensitive SQL')
			$script:h.Failures['log Warning'] = [InvalidOperationException]::new('log failed')
			try {
				Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
				throw 'Expected execution failure'
			}
			catch {
				$_.Exception.ToString() | Should -Match 'original opening failure'
				[object]::ReferenceEquals($_.Exception.GetBaseException(), $script:h.Failures['open Destination']) | Should -BeTrue
				$_.ScriptStackTrace | Should -Match 'Initialize'
				$entries = $_.Exception.Data['Fast1Archiving.CleanupFailures']
				$entries.ResourceRole -join ',' | Should -Match 'Log,DestinationConnection,SourceConnection'
				$entries | ConvertTo-Json | Should -Not -Match 'Password=|secret|sensitive SQL'
			}
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'returns cleanup-only failure after durable completion and keeps attempting releases' {
		InModuleScope ArchivingModel {
			$script:h.Failures['release Destination'] = [InvalidOperationException]::new('disposal failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*disposal failed*'
			$script:h.Persisted[11].ContainsKey('CompleteDate') | Should -BeTrue
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'merges nested cleanup contexts from wrapped errors before their enclosing disposal context' {
		InModuleScope ArchivingModel {
			$nested = [InvalidOperationException]::new('outer disposal failure')
			$nested.Data['Fast1Sql.CleanupFailures'] = @([pscustomobject]@{ Action = 'Dispose'; ResourceRole = 'NestedCommand'; ErrorType = 'Controlled'; Message = 'Nested cleanup failed.' })
			$script:h.Failures['open Destination'] = [InvalidOperationException]::new('primary failure')
			$script:h.Failures['release Destination'] = $nested
			try {
				Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
				throw 'Expected failure'
			}
			catch {
				$_.Exception.Message | Should -Match 'primary failure'
				$entries = $_.Exception.Data['Fast1Archiving.CleanupFailures']
				$entries.ResourceRole -join ',' | Should -Be 'NestedCommand,DestinationConnection'
				$entries.GroupName -join ',' | Should -Be 'controlled,controlled'
			}
		}
	}

	It 'returns drop failure after completion without rewriting the committed marker' {
		InModuleScope ArchivingModel {
			$script:h.Failures['drop 11'] = [InvalidOperationException]::new('drop failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*drop failed*'
			$script:h.Persisted[11].ContainsKey('CompleteDate') | Should -BeTrue
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'rejects reuse of an owner after a no-work execution' {
		InModuleScope ArchivingModel {
			$script:h.Tables = @()
			$group = [TableGroup]::new('Server=controlled;Database=config', 'controlled')
			$group.Execute('')
			{ $group.Execute('') } | Should -Throw '*single-use*'
		}
	}

	It 'retains reconciliation during purge-only preparation' {
		InModuleScope ArchivingModel {
			$script:h.Tables = @(@{ Id = 11; Archive = $false; Purge = $true; PurgeOrder = 1 })
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events | Should -Contain 'snapshot create 11'
			$script:h.Events | Should -Contain 'snapshot copy 11'
			$script:h.Events | Should -Not -Contain 'copy 11 0'
			$script:h.Events | Should -Contain 'delete 11 0'
		}
	}

	It 'releases unknown and empty group resources' {
		InModuleScope ArchivingModel {
			$script:h.Found = $false
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*not found*'
			$script:h.Events[-1] | Should -Be 'release Configuration'
			$script:h.Found = $true
			$script:h.Tables = @()
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'finishes supplied preparation/archive traversal before sorted purging and skips disabled tables' {
		InModuleScope ArchivingModel {
			$script:h.Tables = @(
				@{ Id = 12; Archive = $true; Purge = $true; PurgeOrder = 2 }
				@{ Id = 11; Archive = $true; Purge = $true; PurgeOrder = 1 }
				@{ Id = 13; Archive = $false; Purge = $false; PurgeOrder = 3 }
			)
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events.IndexOf('prepare 12') | Should -BeLessThan $script:h.Events.IndexOf('prepare 11')
			$script:h.Events.IndexOf('copy 11 4') | Should -BeLessThan $script:h.Events.IndexOf('delete 11 0')
			$script:h.Events.IndexOf('delete 11 0') | Should -BeLessThan $script:h.Events.IndexOf('delete 12 0')
			$script:h.Events | Should -Not -Contain 'prepare 13'
			$script:h.Instances[0].KeyCopyBatchSize | Should -Be 3
			$script:h.Instances[0].DataCopyBatchSize | Should -Be 2
			$script:h.Instances[0].PurgeBatchSize | Should -Be 2
			@($script:h.Events | Where-Object { $_ -eq 'delay 1' }).Count | Should -Be 12
			Should -Invoke Invoke-ArchivingConstraintAction -Exactly -Times 0
		}
	}

	It 'restores the whole registered scope after partial disable and gates completion on cleanup success' {
		InModuleScope ArchivingModel {
			$script:h.Constraints = @(
				[pscustomobject]@{ DatabaseName = 'source'; SchemaName = 'dbo'; TableName = 'child'; ConstraintName = 'first' }
				[pscustomobject]@{ DatabaseName = 'source'; SchemaName = 'dbo'; TableName = 'child'; ConstraintName = 'second' }
			)
			$script:h.Failures['constraint first True'] = [InvalidOperationException]::new('disable failed')
			$script:h.Failures['constraint first False'] = [InvalidOperationException]::new('restore failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*disable failed*'
			$script:h.Events | Should -Contain 'constraint second False'
			$script:h.Events.IndexOf('constraint second False') | Should -BeLessThan $script:h.Events.IndexOf('release Source')
			$script:h.Events | Should -Not -Contain 'write 11 PurgeCompleteDate'
			$script:h.Events | Should -Not -Contain 'write 11 CompleteDate'
		}
	}

	It 'keeps attempting command and connection cleanup when a reader release fails' {
		InModuleScope ArchivingModel {
			$script:h.Failures['release reader dbo.stp_GetTableGroup'] = [InvalidOperationException]::new('reader disposal failed')
			$script:h.Failures['release command dbo.stp_GetTableGroup'] = [InvalidOperationException]::new('command disposal failed')
			try {
				Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
				throw 'Expected failure'
			}
			catch {
				$_.Exception.Message | Should -Match 'reader disposal failed'
				$entries = $_.Exception.Data['Fast1Archiving.CleanupFailures']
				$entries.ResourceRole -join ',' | Should -Match 'Reader,Command'
				$entries.GroupName | Should -Contain 'controlled'
			}
			$script:h.Events | Should -Contain 'release command dbo.stp_GetTableGroup'
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'releases streaming readers before checkpoint reuse through the actual batch operation' {
		InModuleScope ArchivingModel {
			$script:h.RealCopy = $true
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events.IndexOf('bulk write') | Should -BeLessThan $script:h.Events.IndexOf('release reader dbo.stp_GetBulkCopyData')
			$script:h.Events.IndexOf('release reader dbo.stp_GetBulkCopyData') | Should -BeLessThan $script:h.Events.IndexOf('write 11 LastArchivedKey')
			$script:h.Persisted[11].RowsArchived | Should -Be 0
			$script:h.Persisted[11].LastArchivedKey | Should -Be 6
		}
	}

	It 'preserves bulk failure and independently releases bulk, reader, command and connections' {
		InModuleScope ArchivingModel {
			$script:h.RealCopy = $true
			$script:h.Failures['bulk write'] = [InvalidOperationException]::new('copy failed')
			$script:h.Failures['release bulk'] = [InvalidOperationException]::new('bulk disposal failed')
			$script:h.Failures['release reader dbo.stp_GetBulkCopyData'] = [InvalidOperationException]::new('reader disposal failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*copy failed*'
			$script:h.Events | Should -Contain 'release command dbo.stp_GetBulkCopyData'
			$script:h.Events | Should -Not -Contain 'write 11 LastArchivedKey'
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}
}

Describe 'Shared SQL command setup and release' {
	BeforeEach {
		InModuleScope ArchivingModel {
			$script:helperConnection = [Microsoft.Data.SqlClient.SqlConnection]::new()
			$script:helperCommand = [Microsoft.Data.SqlClient.SqlCommand]::new()
			$script:helperStatus = [pscustomobject]@{ Released = $false; FailRelease = $false; Execution = '' }
			$script:helperCommand | Add-Member -NotePropertyName Status -NotePropertyValue $script:helperStatus
			$script:helperCommand | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
				$this.Status.Released = $true
				if ($this.Status.FailRelease) {
					throw 'command cleanup failed'
				}
				$this.psbase.Dispose()
			}
			$script:helperCommand | Add-Member -MemberType ScriptMethod -Name ExecuteScalar -Force -Value {
				$this.Status.Execution = 'scalar'
				123
			}
			$script:helperCommand | Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Force -Value {
				$this.Status.Execution = 'non-query'
				-1
			}
			Mock Get-GenericSqlCommand { $script:helperCommand }
		}
	}

	AfterEach {
		InModuleScope ArchivingModel { $script:helperConnection.Dispose() }
	}

	It 'disposes on parameter validation failure without masking the primary error' {
		InModuleScope ArchivingModel {
			$script:helperStatus.FailRelease = $true
			try {
				Invoke-GenericSqlQuery -SqlConn $script:helperConnection -Query 'unused' -Parameters @{ invalid = 'wrong type' }
				throw 'Expected validation failure'
			}
			catch {
				$_.Exception.Message | Should -Match 'must be of type GenericSqlParam'
				$_.Exception.Data['Fast1Sql.CleanupFailures'].ResourceRole | Should -Contain 'Command'
			}
			$script:helperStatus.Released | Should -BeTrue
			$script:helperStatus.Execution | Should -Be ''
		}
	}

	It 'retains scalar, non-query and typed null/size/precision/scale mapping' {
		InModuleScope ArchivingModel {
			$value = Invoke-GenericSqlQuery -SqlConn $script:helperConnection -Query 'unused' -Scalar -CommandType StoredProcedure -Parameters @{
				text = [GenericSqlParam]@{ Value = $null; Type = [System.Data.SqlDbType]::NVarChar; Size = 20 }
				number = [GenericSqlParam]@{ Value = 1.25; Type = [System.Data.SqlDbType]::Decimal; Precision = 8; Scale = 2 }
			}
			$value | Should -Be 123
			$script:helperCommand.Parameters['@text'].Value | Should -Be ([DBNull]::Value)
			$script:helperCommand.Parameters['@text'].Size | Should -Be 20
			$script:helperCommand.Parameters['@number'].Precision | Should -Be 8
			$script:helperCommand.Parameters['@number'].Scale | Should -Be 2
			$script:helperStatus.Released | Should -BeTrue
			@(Invoke-GenericSqlQuery -SqlConn $script:helperConnection -Query 'unused').Count | Should -Be 0
			$script:helperStatus.Execution | Should -Be 'non-query'
		}
	}
}
