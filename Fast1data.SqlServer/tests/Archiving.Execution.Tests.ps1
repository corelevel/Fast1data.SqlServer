using module ../private/shared/GenericSqlParam.psm1

BeforeAll {
	. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent $PSScriptRoot)
	InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$group = [TableGroup]::new('not a connection string', 'controlled')
			$group.ArcSqlConn | Should -BeNullOrEmpty
			$group.SrcSqlConn | Should -BeNullOrEmpty
			$group.DstSqlConn | Should -BeNullOrEmpty
		}
	}


	It 'retains the public parameter and export contract' {
		$command = Get-Command Invoke-Fast1Archiving
		foreach ($name in @('ConnStr', 'GroupName')) {
			$command.Parameters[$name].ParameterType | Should -Be ([string])
		}
		foreach ($name in @('ConnStr', 'GroupName')) {
			$attributes = $command.Parameters[$name].Attributes |
				Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

			$attributes.Mandatory | Should -Contain $true
		}
		@(Get-Command -Module Fast1data.SqlServer).Count | Should -Be 6
	}
}

Describe 'Execution lifetime, transitions and cleanup through the same request' {
	BeforeEach {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h = [PSCustomObject]@{
				Events = [System.Collections.Generic.List[string]]::new()
				Failures = @{}
				CommitThenThrow = ''
				Found = $true
				Tables = @(@{ Id = 11; Archive = $true; Purge = $true; PurgeOrder = 1; BulkCopyTimeout = 30 })
				Persisted = @{}
				Instances = [System.Collections.Generic.List[object]]::new()
				Constraints = @()
				RealCopy = $false
				ActualSource = $false
				ActualDestination = $false
				MissingTimeout = $false
				EmptyCopy = $false
				Writes = [System.Collections.Generic.List[object]]::new()
				Commands = [System.Collections.Generic.List[object]]::new()
			}
			$script:h | Add-Member -MemberType ScriptMethod -Name Record -Value {
				param ([string]$RecordedEvent)
				$this.Events.Add($RecordedEvent)
				if ($this.Failures.ContainsKey($RecordedEvent)) {
					throw $this.Failures[$RecordedEvent]
				}
			}
			Mock Get-ArchivingConnection -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
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
			Mock Get-ArchivingServerIdentity -ModuleName 'Fast1data.SqlServer/ArchivingModel' { 'controlled-instance' }
			Mock Get-ArchivingCommand -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
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
							$values = @{ SourceTableId = $table.Id; SchemaName = 'dbo'; TableName = "t$($table.Id)"; DataCopyBatchSize = 2; KeyCopyBatchSize = 3; PurgeBatchSize = 2; KeyQuery = 'controlled keys'; Archive = $table.Archive; Purge = $table.Purge; PurgeOrder = [short]$table.PurgeOrder; DelayInterval = '00:00:01'; AlwaysRunCheck = $false; SrcWorkingTableName = "w$($table.Id)"; DstWorkingTableName = "d$($table.Id)"; WorkingTableKeyName = 'position'; WorkingTableFlagName = 'skip' }
							if (-not $script:h.MissingTimeout) {
								$values.BulkCopyTimeout = 30
								if ($table.ContainsKey('BulkCopyTimeout')) {
									$values.BulkCopyTimeout = $table.BulkCopyTimeout
								}
							}
							$values
						}
					)
				}
				elseif ($Query -eq 'dbo.stp_GetBulkCopyData') {
					$rows = @(@{ Id = 1 }, @{ Id = 2 })
				}
				elseif ($Query -eq 'controlled keys' -or $Query -eq '') {
					$rows = @(@{ Id = 1 }, @{ Id = 2 })
				}
				elseif ($Query -match 'select top \(@PageSize\)') {
					# Read these rows after parameters are supplied by the real method.
					$rows = @()
				}
				else {
					throw "Unexpected SQL in controlled suite: $Query"
				}
				$command = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $Connection)
				$script:h.Commands.Add($command)
				$command | Add-Member -NotePropertyName Harness -NotePropertyValue $script:h
				$command | Add-Member -NotePropertyName TestReader -NotePropertyValue (Get-ControlledReader -Rows $rows -Role $Query)
				$command | Add-Member -MemberType ScriptMethod -Name ExecuteReader -Force -Value {
					$this.Harness.Record("read $($this.CommandText)")
					if ($this.CommandText -match 'select top \(@PageSize\)') {
						$rows = @(
							foreach ($id in 1..5) {
								if (-not $this.Harness.EmptyCopy -and $id -gt $this.Parameters['@After'].Value) {
									@{ position = $id; Id = $id }
								}
							}
						) | Select-Object -First $this.Parameters['@PageSize'].Value
						# The real method reads position at ordinal zero.
						$data = [System.Data.DataTable]::new()
						[void]$data.Columns.Add('position', [int])
						[void]$data.Columns.Add('Id', [int])
						foreach ($row in $rows) {
							[void]$data.Rows.Add($row.position, $row.Id)
						}
						$this.TestReader.Dispose()
						$this.TestReader = $data.CreateDataReader()
					}
					elseif ($this.Harness.EmptyCopy -and $this.CommandText -ne 'dbo.stp_GetSourceTable' -and $this.CommandText -ne 'dbo.stp_GetTableGroup') {
						$this.TestReader.Dispose()
						$this.TestReader = Get-ControlledReader -Rows @() -Role $this.CommandText
					}
					if ($this.TestReader.PSObject.Properties['Role']) {
						$this.TestReader.Role = $this.CommandText
					}
					return ,$this.TestReader
				}
				$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Harness.Record("release command $($this.CommandText)")
					$this.psbase.Dispose()
				}
				$command
			}
			Mock Get-ArchivingTable -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
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
					$this.SrcColumns.Add('Id', [TableColumn]@{ Name = 'Id'; DataType = 'int'; SqlType = 'int' })
				}
				$table | Add-Member -MemberType ScriptMethod -Name ReadDstTableColumns -Force -Value { $this.DstColumns = $this.SrcColumns }
				$table | Add-Member -MemberType ScriptMethod -Name AddMissedColumns -Force -Value { $false }
				$table | Add-Member -MemberType ScriptMethod -Name GetState -Force -Value {
					if (-not $this.Harness.Persisted.ContainsKey($this.Id)) {
						$this.Harness.Persisted[$this.Id] = @{ Id = $this.Id + 100; SourceTableId = $this.Id; KeyMaxValue = 5; KeyCopyDate = [datetime]::Now; LastArchivedKey = 0; RowsArchived = 0; LastPurgedKey = 0; RowsPurged = 0; IncompleteProcess = $true }
					}
					$this.State = [ProcessState]($this.Harness.Persisted[$this.Id] + @{ ArcSqlConn = $this.Group.ArcSqlConn })
					if ($this.Harness.ActualSource) {
						$this.State.KeyCopyDate = [datetime]::MinValue
					}
					$this.Harness.Record("load $($this.Id) $($this.State.LastArchivedKey)")
				}
				$table | Add-Member -MemberType ScriptMethod -Name CreateDestinationWorkingTable -Force -Value { $this.Harness.Record("snapshot create $($this.Id)") }
				$table | Add-Member -MemberType ScriptMethod -Name CreateSourceWorkingTable -Force -Value { $this.Harness.Record("capture create $($this.Id)") }
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
				if ($script:h.ActualDestination) {
					$table.PSObject.Methods.Remove('BulkCopyDestinationPK')
				}
				$table
			}
			Mock Get-ArchivingBulkCopy -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
				param ($Connection, [Microsoft.Data.SqlClient.SqlBulkCopyOptions]$Options = 0)
				$bulk = [Microsoft.Data.SqlClient.SqlBulkCopy]::new($Connection, $Options, $null)
				$bulk | Add-Member -NotePropertyName Harness -NotePropertyValue $script:h
				$bulk | Add-Member -NotePropertyName CopyOptions -NotePropertyValue $Options
				$bulk | Add-Member -MemberType ScriptMethod -Name WriteToServer -Force -Value {
					param ($Reader)
					$null = $Reader
					$this.Harness.Writes.Add([pscustomobject]@{
						Target = $this.DestinationTableName
						Timeout = $this.BulkCopyTimeout
						Streaming = $this.EnableStreaming
						BatchSize = $this.BatchSize
						Options = $this.CopyOptions
						Mappings = @($this.ColumnMappings | ForEach-Object { "$($_.SourceColumn):$($_.DestinationColumn)" })
					})
					$this.Harness.Record('bulk write')
				}
				$bulk | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Harness.Record('release bulk')
					$this.psbase.Dispose()
				}
				$bulk
			}
			Mock Invoke-Fast1GenericSqlQuery -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
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
			Mock Invoke-ArchivingConstraintAction -ModuleName 'Fast1data.SqlServer/ArchivingModel' {
				param ($Constraint, $Disable)
				$script:h.Record("constraint $($Constraint.ConstraintName) $Disable")
			}
			Mock Start-Sleep -ModuleName 'Fast1data.SqlServer/ArchivingModel' { $script:h.Record("delay $Seconds") }
		}
	}

	It 'loads independent typed timeout values in <Order> traversal order' -ForEach @(
		@{ Order = 'forward'; Values = @(60, 120) }
		@{ Order = 'reverse'; Values = @(120, 60) }
	) {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' -Parameters @{ Values = $Values } {
			$script:h.Tables = @(
				@{ Id = 11; Archive = $false; Purge = $false; PurgeOrder = 1; BulkCopyTimeout = $Values[0] }
				@{ Id = 12; Archive = $false; Purge = $false; PurgeOrder = 2; BulkCopyTimeout = $Values[1] }
			)
			Invoke-Fast1Archiving -ConnStr 'Server=controlled' -GroupName controlled
			$script:h.Instances | Should -HaveCount 2
			for ($index = 0; $index -lt 2; $index++) {
				$script:h.Instances[$index] | Should -BeOfType ([Table])
				$script:h.Instances[$index].BulkCopyTimeout | Should -Be $Values[$index]
				$script:h.Instances[$index].BulkCopyTimeout | Should -BeOfType ([int])
			}
			$script:h.Writes | Should -HaveCount 0
		}
	}

	It 'fails normal metadata loading if the required timeout field is absent' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.MissingTimeout = $true
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled' -GroupName controlled } | Should -Throw '*BulkCopyTimeout*'
			$script:h.Instances | Should -HaveCount 0
		}
	}

	It 'preserves <Timeout> at every actual write across tables, pages and batches' -ForEach @(
		@{ Timeout = 60 }
		@{ Timeout = 120 }
		@{ Timeout = 30 }
		@{ Timeout = 0 }
		@{ Timeout = 2147483647 }
	) {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' -Parameters @{ Timeout = $Timeout } {
			$otherTimeout = 60
			if ($Timeout -eq 60) {
				$otherTimeout = 120
			}
			$script:h.Tables = @(
				@{ Id = 11; Archive = $true; Purge = $false; PurgeOrder = 1; BulkCopyTimeout = $Timeout }
				@{ Id = 12; Archive = $true; Purge = $false; PurgeOrder = 2; BulkCopyTimeout = $otherTimeout }
			)
			$script:h.RealCopy = $true
			$script:h.ActualDestination = $true
			$group = [TableGroup]::new('Server=controlled;Command Timeout=2', 'controlled')
			try {
				$group.Initialize()
				$group.ReadSourceTables()
				foreach ($table in $group.SourceTables) {
					$table.ReadSrcTableColumns()
					$table.GetState()
					$table.BulkCopySourcePK()
					$table.BulkCopyDestinationPK()
					$table.ExecuteArchive()
					$writes = @($script:h.Writes | Where-Object { $_.Target -in @($table.SrcWorkingTableName, "dbo.[$($table.DstWorkingTableName)]", "[dbo].[$($table.TableName)]") })
					$writes | Should -HaveCount 6
					foreach ($write in $writes) {
						$write.Timeout | Should -Be $table.BulkCopyTimeout
						$write.Streaming | Should -BeTrue
						$write.Mappings -join ',' | Should -Be 'Id:Id'
						if ($write.Target -eq "[dbo].[$($table.TableName)]") {
							$write.BatchSize | Should -Be 2
							[int]$write.Options | Should -Be ([int]([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity -bor [Microsoft.Data.SqlClient.SqlBulkCopyOptions]::KeepNulls))
						}
						else {
							$write.BatchSize | Should -Be 3
							[int]$write.Options | Should -Be 0
						}
					}
				}
				$script:h.Commands[0].CommandTimeout | Should -Be 2
				$script:h.Commands[1].CommandTimeout | Should -Be 2
				# Source/destination options retain their independent provider default.
				@($script:h.Commands | Where-Object { $_.CommandTimeout -notin @(2, 30) }) | Should -HaveCount 0
			}
			finally {
				$group.Dispose()
			}
		}
	}

	It 'loads the configured timeout and skips empty source and archive readers' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.RealCopy = $true
			$script:h.ActualDestination = $true
			$script:h.EmptyCopy = $true
			$group = [TableGroup]::new('Server=controlled', 'controlled')
			try {
				$group.Initialize()
				$group.ReadSourceTables()
				$table = $group.SourceTables[0]
				$table.BulkCopyTimeout | Should -Be 30
				$table.ReadSrcTableColumns()
				$table.GetState()
				$table.BulkCopySourcePK()
				$table.BulkCopyDestinationPK()
				$table.BulkCopyTable()
				$script:h.Writes | Should -HaveCount 0
				$script:h.Events | Should -Contain 'release reader controlled keys'
				$script:h.Events | Should -Contain 'release reader dbo.stp_GetBulkCopyData'
			}
			finally {
				$group.Dispose()
			}
		}
	}

	It 'retains primary failure and prevents checkpoints at the actual <Stage> write' -ForEach @(
		@{ Stage = 'source'; Reader = 'controlled keys'; Source = $true; Destination = $false; Archive = $false }
		@{ Stage = 'destination'; Reader = 'set nocount on; select [Id] from [dbo].[t11] where ([Id] = @k0_0) or ([Id] = @k1_0) or ([Id] = @k2_0)'; Source = $false; Destination = $true; Archive = $false }
		@{ Stage = 'archive'; Reader = 'dbo.stp_GetBulkCopyData'; Source = $false; Destination = $false; Archive = $true }
	) {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' -Parameters @{ Reader = $Reader; Source = $Source; Destination = $Destination; Archive = $Archive } {
			$script:h.ActualSource = $Source
			$script:h.ActualDestination = $Destination
			$script:h.RealCopy = $Archive
			$script:h.Failures['bulk write'] = [OperationCanceledException]::new('write interrupted')
			$script:h.Failures['release bulk'] = [InvalidOperationException]::new('bulk disposal failed')
			$script:h.Failures["release reader $Reader"] = [InvalidOperationException]::new('reader disposal failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled' -GroupName controlled } | Should -Throw '*write interrupted*'
			$script:h.Events | Should -Contain "release command $Reader"
			$script:h.Events | Should -Contain "release reader $Reader"
			$script:h.Events | Should -Contain 'release bulk'
			$script:h.Events | Should -Not -Contain 'write 11 LastArchivedKey'
			$script:h.Events | Should -Not -Contain 'write 11 CompleteDate'
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'constructs and executes exactly once with real nested verbose messages' {
		$messages = @(Invoke-Fast1Archiving -ConnStr 'Server=controlled' -GroupName controlled -Verbose 4>&1)
		$messages | Should -HaveCount 3
		$messages[0].Message | Should -Match '\[Verbose\] Archive group \(controlled\) found$'
		$messages[1].Message | Should -Match 'Archiving completed for \[dbo\]\.\[t11\]'
		$messages[2].Message | Should -Match 'Purging completed for \[dbo\]\.\[t11\]'
		foreach ($record in $messages) {
			$record | Should -BeOfType ([System.Management.Automation.VerboseRecord])
		}
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			@($script:h.Events | Where-Object { $_ -eq 'allocate Configuration' }).Count | Should -Be 1
			@($script:h.Events | Where-Object { $_ -eq 'write 11 CompleteDate' }).Count | Should -Be 1
			@($script:h.Events | Where-Object { $_ -eq 'release Configuration' }).Count | Should -Be 1
		}
	}

	It 'releases every allocated connection when <Role> opening fails' -ForEach @(
		@{ Role = 'Source'; Released = 'release Source,release Configuration' }
		@{ Role = 'Destination'; Released = 'release Destination,release Source,release Configuration' }
	) {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' -Parameters @{ Role = $Role; Released = $Released } {
			$script:h.Failures["open $Role"] = [InvalidOperationException]::new('opening failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*opening failed*'
			@($script:h.Events | Where-Object { $_ -match '^release (Source|Destination|Configuration)$' }) -join ',' | Should -Be $Released
		}
	}

	It 'owns successful batches, resets activity, confirms effects then completion and releases connections' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' -Parameters @{ Fault = $Fault } {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.Failures['open Destination'] = [InvalidOperationException]::new('original opening failure')
			$script:h.Failures['release Destination'] = [InvalidOperationException]::new('Password=secret')
			$script:h.Failures['release Source'] = [InvalidOperationException]::new('sensitive SQL')
			Mock Write-LogMessage -ModuleName 'Fast1data.SqlServer/ArchivingModel' { $script:h.Record("log $Level") }
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.Failures['release Destination'] = [InvalidOperationException]::new('disposal failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*disposal failed*'
			$script:h.Persisted[11].ContainsKey('CompleteDate') | Should -BeTrue
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'merges nested cleanup contexts from wrapped errors before their enclosing disposal context' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$nested = [InvalidOperationException]::new('outer disposal failure')
			$nested.Data['Fast1Sql.CleanupFailures'] = @([PSCustomObject]@{ Action = 'Dispose'; ResourceRole = 'NestedCommand'; ErrorType = 'Controlled'; Message = 'Nested cleanup failed.' })
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.Failures['drop 11'] = [InvalidOperationException]::new('drop failed')
			{ Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled' } | Should -Throw '*drop failed*'
			$script:h.Persisted[11].ContainsKey('CompleteDate') | Should -BeTrue
			$script:h.Events[-1] | Should -Be 'release Configuration'
		}
	}

	It 'rejects reuse of an owner after a no-work execution' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.Tables = @()
			$group = [TableGroup]::new('Server=controlled;Database=config', 'controlled')
			$group.Execute()
			{ $group.Execute() } | Should -Throw '*single-use*'
		}
	}

	It 'retains reconciliation during purge-only preparation' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.Tables = @(@{ Id = 11; Archive = $false; Purge = $true; PurgeOrder = 1 })
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events | Should -Contain 'snapshot create 11'
			$script:h.Events | Should -Contain 'snapshot copy 11'
			$script:h.Events | Should -Not -Contain 'copy 11 0'
			$script:h.Events | Should -Contain 'delete 11 0'
		}
	}

	It 'releases unknown and empty group resources' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
			Should -Invoke Invoke-ArchivingConstraintAction -ModuleName 'Fast1data.SqlServer/ArchivingModel' -Exactly -Times 0
		}
	}

	It 'restores the whole registered scope after partial disable and gates completion on cleanup success' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.Constraints = @(
				[PSCustomObject]@{ DatabaseName = 'source'; SchemaName = 'dbo'; TableName = 'child'; ConstraintName = 'first' }
				[PSCustomObject]@{ DatabaseName = 'source'; SchemaName = 'dbo'; TableName = 'child'; ConstraintName = 'second' }
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:h.RealCopy = $true
			Invoke-Fast1Archiving -ConnStr 'Server=controlled;Database=config' -GroupName 'controlled'
			$script:h.Events.IndexOf('bulk write') | Should -BeLessThan $script:h.Events.IndexOf('release reader dbo.stp_GetBulkCopyData')
			$script:h.Events.IndexOf('release reader dbo.stp_GetBulkCopyData') | Should -BeLessThan $script:h.Events.IndexOf('write 11 LastArchivedKey')
			$script:h.Persisted[11].RowsArchived | Should -Be 0
			$script:h.Persisted[11].LastArchivedKey | Should -Be 6
		}
	}

	It 'preserves bulk failure and independently releases bulk, reader, command and connections' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:helperConnection = [Microsoft.Data.SqlClient.SqlConnection]::new()
			$script:helperCommand = [Microsoft.Data.SqlClient.SqlCommand]::new()
			$script:helperStatus = [PSCustomObject]@{ Released = $false; FailRelease = $false; Execution = '' }
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
			Mock Get-GenericSqlCommand -ModuleName 'Fast1data.SqlServer/ArchivingModel' { $script:helperCommand }
		}
	}

	AfterEach {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' { $script:helperConnection.Dispose() }
	}

	It 'disposes on parameter validation failure without masking the primary error' {
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$script:helperStatus.FailRelease = $true
			try {
				Invoke-Fast1GenericSqlQuery -SqlConn $script:helperConnection -Query 'unused' -Parameters @{ invalid = 'wrong type' }
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
		InModuleScope 'Fast1data.SqlServer/ArchivingModel' {
			$value = Invoke-Fast1GenericSqlQuery -SqlConn $script:helperConnection -Query 'unused' -Scalar -CommandType StoredProcedure -Parameters @{
				text = [GenericSqlParam]@{ Value = $null; Type = [System.Data.SqlDbType]::NVarChar; Size = 20 }
				number = [GenericSqlParam]@{ Value = 1.25; Type = [System.Data.SqlDbType]::Decimal; Precision = 8; Scale = 2 }
			}
			$value | Should -Be 123
			$script:helperCommand.Parameters['@text'].Value | Should -Be ([DBNull]::Value)
			$script:helperCommand.Parameters['@text'].Size | Should -Be 20
			$script:helperCommand.Parameters['@number'].Precision | Should -Be 8
			$script:helperCommand.Parameters['@number'].Scale | Should -Be 2
			$script:helperStatus.Released | Should -BeTrue
			@(Invoke-Fast1GenericSqlQuery -SqlConn $script:helperConnection -Query 'unused').Count | Should -Be 0
			$script:helperStatus.Execution | Should -Be 'non-query'
		}
	}
}
