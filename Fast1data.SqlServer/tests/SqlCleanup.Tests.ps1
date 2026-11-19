BeforeAll {
	. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent $PSScriptRoot)
	InModuleScope Fast1data.SqlServer {
		$script:cleanupImplementation = (Get-Command Close-GenericSqlResource).ScriptBlock
	}
}

Describe 'Shared SQL resource cleanup in <Owner>' -ForEach @(@{ Owner = 'Fast1data.SqlServer' }, @{ Owner = 'ArchivingModel' }) {
	It 'attempts every resource in order and throws the first cleanup failure after releasing the rest' {
		InModuleScope $Owner {
			$events = [System.Collections.Generic.List[string]]::new()
			$resources = [ordered]@{ Unallocated = $null }
			foreach ($role in @('Reader', 'Command', 'Connection')) {
				$resource = [PSCustomObject]@{ Role = $role; Events = $events }
				$resource | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
					$this.Events.Add($this.Role)
					if ($this.Role -ne 'Connection') {
						throw "$($this.Role) cleanup failed"
					}
				}
				$resources[$role] = $resource
			}
			$caught = $null
			try {
				Close-GenericSqlResource -Resources $resources
			}
			catch {
				$caught = $_
			}

			$events -join ',' | Should -Be 'Reader,Command,Connection'
			$caught.Exception.Message | Should -BeLike '*Reader cleanup failed*'
			$failures = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$failures.ResourceRole -join ',' | Should -Be 'Reader,Command'
			$failures.Message | Should -Not -Contain 'Reader cleanup failed'
		}
	}

	It 'releases successful resources without emitting output' {
		InModuleScope $Owner {
			$resource = [PSCustomObject]@{ Released = $false }
			$resource | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
				$this.Released = $true
			}

			$result = @(Close-GenericSqlResource -Resources ([ordered]@{ Reader = $null; Command = $resource }))

			$result | Should -BeNullOrEmpty
			$resource.Released | Should -BeTrue
		}
	}
}

Describe 'Audit and migration cleanup on operation failure' {
	BeforeEach {
		InModuleScope Fast1data.SqlServer {
			$script:cleanupState = [PSCustomObject]@{
				PrimaryError = $null
				Roles = @()
				Released = [System.Collections.Generic.List[string]]::new()
			}
			Mock Get-SqlAuditFile {
				[PSCustomObject]@{ AuditGuid = [guid]::Empty }
			}
			Mock Close-GenericSqlResource {
				$script:cleanupState.PrimaryError = $PrimaryError
				$script:cleanupState.Roles = @($Resources.Keys)
				foreach ($role in $Resources.Keys) {
					if ($null -eq $Resources[$role]) {
						continue
					}
					$Resources[$role] | Add-Member -NotePropertyName CleanupState -NotePropertyValue $script:cleanupState
					$Resources[$role] | Add-Member -NotePropertyName CleanupRole -NotePropertyValue $role
					$Resources[$role] | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
						$this.CleanupState.Released.Add($this.CleanupRole)
						$this.psbase.Dispose()
						throw 'Controlled cleanup failure'
					}
				}
				& $script:cleanupImplementation -Resources $Resources -PrimaryError $PrimaryError
			}
		}
	}

	It '<CommandName> preserves its operation error when cleanup also fails' -ForEach @(
		@{ CommandName = 'Get-Executed'; Roles = 'Reader,Command,Connection'; Released = 'Connection' }
		@{ CommandName = 'Get-ImportState'; Roles = 'Reader,Command'; Released = 'Command' }
		@{ CommandName = 'Import-SqlAuditFile'; Roles = 'Reader,Command'; Released = 'Command' }
		@{ CommandName = 'Invoke-Fast1Audit'; Roles = 'Connection'; Released = 'Connection' }
	) {
		InModuleScope Fast1data.SqlServer -Parameters @{ CommandName = $CommandName; Roles = $Roles; Released = $Released } {
			$connection = [Microsoft.Data.SqlClient.SqlConnection]::new()
			$caught = $null
			try {
				switch ($CommandName) {
					'Get-Executed' {
						Get-Executed -ConnStr 'InvalidKeyword=value' -Phase 'test'
					}
					'Get-ImportState' {
						Get-ImportState -SqlConn $connection -AuditGuids @([guid]::Empty)
					}
					'Import-SqlAuditFile' {
						Import-SqlAuditFile -SqlConn $connection -Folder 'unused' -AuditGuid ([guid]::Empty)
					}
					'Invoke-Fast1Audit' {
						Invoke-Fast1Audit -ConnStr 'InvalidKeyword=value' -Folder 'unused'
					}
				}
			}
			catch {
				$caught = $_
			}
			finally {
				$connection.Dispose()
			}

			$caught | Should -Not -BeNullOrEmpty
			[object]::ReferenceEquals($caught.Exception, $script:cleanupState.PrimaryError.Exception) | Should -BeTrue
			$script:cleanupState.Roles -join ',' | Should -Be $Roles
			$script:cleanupState.Released -join ',' | Should -Be $Released
			$failures = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$failures.ResourceRole -join ',' | Should -Be $Released
			Should -Invoke Close-GenericSqlResource -Times 1 -Exactly
		}
	}
}

Describe 'Real query contract in <Owner>' -ForEach @(@{ Owner = 'Fast1data.SqlServer' }, @{ Owner = 'ArchivingModel' }) {
	BeforeEach {
		InModuleScope $Owner {
			$script:queryConnection = [Microsoft.Data.SqlClient.SqlConnection]::new()
			$script:queryState = [PSCustomObject]@{ Released = $false; BorrowedReleased = $false; ExecuteFailure = $false; CleanupFailure = $false; Execution = '' }
			$script:queryConnection | Add-Member -NotePropertyName Status -NotePropertyValue $script:queryState
			$script:queryConnection | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value { $this.Status.BorrowedReleased = $true }
			Mock Get-GenericSqlCommand {
				param ($Query, $SqlConn)
				$script:queryCommand = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn)
				$script:queryCommand | Add-Member -NotePropertyName Status -NotePropertyValue $script:queryState
				$script:queryCommand | Add-Member -MemberType ScriptMethod -Name ExecuteScalar -Force -Value {
					$this.Status.Execution = 'scalar'
					if ($this.Status.ExecuteFailure) {
						throw 'controlled execution failure'
					}
					123
				}
				$script:queryCommand | Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Force -Value {
					$this.Status.Execution = 'non-query'
					if ($this.Status.ExecuteFailure) {
						throw 'controlled execution failure'
					}
					42
				}
				$script:queryCommand | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Status.Released = $true
					if ($this.Status.CleanupFailure) {
						throw 'controlled cleanup failure'
					}
				}
				$script:queryCommand
			}
		}
	}

	AfterEach {
		InModuleScope $Owner {
			$script:queryConnection.psbase.Dispose()
			if ($null -ne $script:queryCommand) {
				$script:queryCommand.psbase.Dispose()
			}
		}
	}

	It 'preserves text, type, parameter fields, scalar result and borrowed connection ownership' {
		InModuleScope $Owner {
			$fields = [ordered]@{ Value = [object]; Type = [System.Data.SqlDbType]; Size = [int]; Precision = [byte]; Scale = [byte] }
			foreach ($name in $fields.Keys) {
				[GenericSqlParam].GetProperty($name).PropertyType | Should -Be $fields[$name]
			}
			$value = Invoke-GenericSqlQuery -SqlConn $script:queryConnection -Query 'dbo.controlled' -CommandType StoredProcedure -Scalar -Parameters @{
				text = [GenericSqlParam]@{ Value = $null; Type = 'NVarChar'; Size = 20 }
				number = [GenericSqlParam]@{ Value = 1.25; Type = 'Decimal'; Precision = 8; Scale = 2 }
			}
			$value | Should -Be 123
			$script:queryCommand.CommandText | Should -Be 'dbo.controlled'
			$script:queryCommand.CommandType | Should -Be 'StoredProcedure'
			$script:queryCommand.Connection | Should -Be $script:queryConnection
			$script:queryCommand.Parameters.Count | Should -Be 2
			$script:queryCommand.Parameters['@text'].Value | Should -Be ([DBNull]::Value)
			$script:queryCommand.Parameters['@text'].SqlDbType | Should -Be 'NVarChar'
			$script:queryCommand.Parameters['@text'].Size | Should -Be 20
			$script:queryCommand.Parameters['@number'].Value | Should -Be 1.25
			$script:queryCommand.Parameters['@number'].SqlDbType | Should -Be 'Decimal'
			$script:queryCommand.Parameters['@number'].Precision | Should -Be 8
			$script:queryCommand.Parameters['@number'].Scale | Should -Be 2
			$script:queryState.Released | Should -BeTrue
			$script:queryState.BorrowedReleased | Should -BeFalse
		}
	}

	It 'emits no non-query success output and retains default text command type' {
		InModuleScope $Owner {
			@(Invoke-GenericSqlQuery -SqlConn $script:queryConnection -Query 'controlled').Count | Should -Be 0
			$script:queryCommand.CommandText | Should -Be 'controlled'
			$script:queryCommand.CommandType | Should -Be 'Text'
			$script:queryState.Execution | Should -Be 'non-query'
			$script:queryState.Released | Should -BeTrue
			$script:queryState.BorrowedReleased | Should -BeFalse
		}
	}

	It 'rejects <Kind> parameters before execution and disposes its command' -ForEach @(
		@{ Kind = 'wrong type'; Message = '*must be of type GenericSqlParam*' }
		@{ Kind = 'missing type'; Message = '*must have Type specified*' }
	) {
		InModuleScope $Owner -Parameters @{ Kind = $Kind; Message = $Message } {
			$parameter = 'wrong'
			if ($Kind -eq 'missing type') {
				$parameter = [GenericSqlParam]::new()
			}
			{ Invoke-GenericSqlQuery -SqlConn $script:queryConnection -Query 'controlled' -Parameters @{ value = $parameter } } | Should -Throw $Message
			$script:queryState.Execution | Should -Be ''
			$script:queryState.Released | Should -BeTrue
			$script:queryState.BorrowedReleased | Should -BeFalse
		}
	}

	It 'preserves construction errors without disposing the borrowed connection' {
		InModuleScope $Owner {
			Mock Get-GenericSqlCommand { throw 'controlled construction failure' }
			{ Invoke-GenericSqlQuery -SqlConn $script:queryConnection -Query 'controlled' } | Should -Throw '*controlled construction failure*'
			$script:queryState.Released | Should -BeFalse
			$script:queryState.BorrowedReleased | Should -BeFalse
		}
	}

	It 'retains the primary error and safe deduplicated cleanup context (primary=<Primary>, cleanup=<Cleanup>)' -ForEach @(
		@{ Primary = $true; Cleanup = $false }
		@{ Primary = $false; Cleanup = $true }
		@{ Primary = $true; Cleanup = $true }
	) {
		InModuleScope $Owner -Parameters @{ Primary = $Primary; Cleanup = $Cleanup } {
			$script:queryState.ExecuteFailure = $Primary
			$script:queryState.CleanupFailure = $Cleanup
			$caught = $null
			try {
				Invoke-GenericSqlQuery -SqlConn $script:queryConnection -Query 'controlled'
			}
			catch {
				$caught = $_
			}
			$caught | Should -Not -BeNullOrEmpty
			if ($Primary) {
				$caught.Exception.Message | Should -Match 'controlled execution failure'
			}
			else {
				$caught.Exception.Message | Should -Match 'controlled cleanup failure'
			}
			$entries = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$entries.Count | Should -Be ([int]$Cleanup)
			if ($Cleanup) {
				$entries[0].ResourceRole | Should -Be 'Command'
				($entries | ConvertTo-Json) | Should -Not -Match 'controlled|ConnectionString|Password'
				@(Get-GenericSqlCleanupFailure -ErrorRecord $caught).Count | Should -Be 1
			}
			$script:queryState.Released | Should -BeTrue
			$script:queryState.BorrowedReleased | Should -BeFalse
		}
	}
}
Describe 'Migration executor owned cleanup' {
	It 'preserves the first failure and attempts all cleanup (batch=<Batch>, command=<Command>, connection=<Connection>, scope=<Scope>)' -ForEach @(
		foreach ($batch in @($false, $true)) {
			foreach ($command in @($false, $true)) {
				foreach ($connection in @($false, $true)) {
					foreach ($scope in @($false, $true)) {
						@{ Batch = $batch; Command = $command; Connection = $connection; Scope = $scope }
					}
				}
			}
		}
	) {
		$path = Join-Path $TestDrive 'cleanup.sql'
		[System.IO.File]::WriteAllText($path, 'SELECT 1;')
		InModuleScope Fast1data.SqlServer -Parameters @{
			Path = $path; Fixture = (Join-Path $PSScriptRoot 'fixtures/Get-MigrationTestCommand.ps1')
			Batch = $Batch; Command = $Command; Connection = $Connection; Scope = $Scope
		} {
			. $Fixture
			$script:execution = Get-MigrationTestExecution
			$script:execution.FailCommandCleanup = $Command
			$script:execution.FailConnectionCleanup = $Connection
			$script:scopeFailure = $Scope
			if ($Batch) {
				$script:execution.Command.FailAt = 1
			}
			Mock Get-MigrationScriptConnection { $script:execution.Connection }
			Mock Get-MigrationScriptCommand { $script:execution.Command }
			Mock Get-MigrationSuppressionScope {
				$scope = [pscustomobject]@{
					Actual = [System.Transactions.TransactionScope]::new([System.Transactions.TransactionScopeOption]::Suppress)
					Events = $script:execution.Events
					FailCleanup = $script:scopeFailure
				}
				$scope | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
					$this.Events.Add('scope-dispose')
					$this.Actual.Dispose()
					if ($this.FailCleanup) {
						throw 'private scope disposal details'
					}
				}
				$scope
			}
			$caught = $null
			$ambient = [System.Transactions.TransactionScope]::new()
			try {
				$callerTransaction = [System.Transactions.Transaction]::Current
				try {
					Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $Path
				}
				catch {
					$caught = $_
				}
				[object]::ReferenceEquals([System.Transactions.Transaction]::Current, $callerTransaction) | Should -BeTrue
				$ambient.Complete()
			}
			finally {
				$ambient.Dispose()
			}
			$script:execution.Events.ToArray() | Should -Be @('open', 'command-dispose', 'connection-dispose', 'scope-dispose')
			if ($Batch -or $Command -or $Connection -or $Scope) {
				$caught | Should -Not -BeNullOrEmpty
				$caught.Exception.Message | Should -Not -Match 'private .* details'
				if ($Batch) {
					$caught.Exception.Message | Should -Match 'batch 1'
				}
				else {
					$caught.Exception.Message | Should -Match 'cleanup'
				}
				$entries = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
				$entries.Count | Should -Be ([int]$Command + [int]$Connection + [int]$Scope)
				$expectedRoles = @(
					if ($Command) {
						'ExecutionCommand'
					}
					if ($Connection) {
						'ExecutionConnection'
					}
					if ($Scope) {
						'SuppressionScope'
					}
				)
				@($entries | Select-Object -ExpandProperty ResourceRole) | Should -Be $expectedRoles
				($entries | ConvertTo-Json) | Should -Not -Match 'private .* details|Server='
			}
			else {
				$caught | Should -BeNullOrEmpty
			}
		}
	}
}
Describe 'Migration public owner cleanup' {
	BeforeAll {
		$script:migrationCleanupBase = Join-Path $TestDrive 'owner'
		$null = New-Item -ItemType Directory -Path (Join-Path $script:migrationCleanupBase 'phase') -Force
		'{"phase":{"scripts":["one.sql"]}}' | Set-Content -LiteralPath (Join-Path $script:migrationCleanupBase 'migration.json')
		'SELECT 1;' | Set-Content -LiteralPath (Join-Path $script:migrationCleanupBase 'phase/one.sql')
	}

	It 'preserves <Failure> while attempting every owned resource (cleanup fails=<CleanupFails>)' -ForEach @(
		foreach ($failure in @('none', 'open', 'script', 'history')) {
			foreach ($cleanup in @($false, $true)) {
				@{ Failure = $failure; CleanupFails = $cleanup }
			}
		}
	) {
		InModuleScope Fast1data.SqlServer -Parameters @{ Base = $script:migrationCleanupBase; Failure = $Failure; CleanupFails = $CleanupFails } {
			$script:ownerFailure = $Failure
			$script:ownerCleanupFails = $CleanupFails
			$script:ownerReleased = [System.Collections.Generic.List[string]]::new()
			Mock Get-Executed { @() }
			Mock Get-MigrationConnection {
				$connection = [Microsoft.Data.SqlClient.SqlConnection]::new()
				$connection | Add-Member -NotePropertyName Events -NotePropertyValue $script:ownerReleased
				$connection | Add-Member -NotePropertyName FailOpen -NotePropertyValue ($script:ownerFailure -eq 'open')
				$connection | Add-Member -NotePropertyName FailCleanup -NotePropertyValue $script:ownerCleanupFails
				$connection | Add-Member -MemberType ScriptMethod -Name Open -Force -Value {
					if ($this.FailOpen) {
						throw 'controlled open failure'
					}
				}
				$connection | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Events.Add('Connection')
					if ($this.FailCleanup) {
						throw 'controlled connection cleanup failure'
					}
				}
				$connection
			}
			Mock Get-GenericSqlCommand {
				$command = [Microsoft.Data.SqlClient.SqlCommand]::new('', $SqlConn)
				$command | Add-Member -NotePropertyName Events -NotePropertyValue $script:ownerReleased
				$command | Add-Member -NotePropertyName FailCleanup -NotePropertyValue $script:ownerCleanupFails
				$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
					$this.Events.Add('Command')
					if ($this.FailCleanup) {
						throw 'controlled command cleanup failure'
					}
				}
				$command
			}
			Mock Invoke-Migration {
				if ($script:ownerFailure -eq 'script') {
					throw 'controlled script failure'
				}
			}
			Mock Set-Executed {
				if ($script:ownerFailure -eq 'history') {
					throw 'controlled history failure'
				}
			}
			$caught = $null
			try {
				Invoke-Fast1Migration -ConnStr 'Server=unused;Database=unused' -BasePath $Base -Phase phase -Confirm:$false
			}
			catch {
				$caught = $_
			}
			$expected = @('Command', 'Connection')
			if ($Failure -eq 'open') {
				$expected = @('Connection')
			}
			$script:ownerReleased.ToArray() | Should -Be $expected
			if ($Failure -eq 'none' -and -not $CleanupFails) {
				$caught | Should -BeNullOrEmpty
			}
			elseif ($Failure -eq 'open') {
				$caught.Exception.Message | Should -Match 'could not open mutation resources'
				$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
			}
			elseif ($Failure -ne 'none') {
				$caught.Exception.Message | Should -Match "controlled $Failure failure"
			}
			else {
				$caught.Exception.Message | Should -Match 'controlled command cleanup failure'
			}
			if ($CleanupFails) {
				@(Get-GenericSqlCleanupFailure -ErrorRecord $caught).ResourceRole | Should -Be $expected
			}
		}
	}
}
