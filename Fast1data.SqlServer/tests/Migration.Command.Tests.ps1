BeforeAll {
	. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent $PSScriptRoot)
	. (Join-Path $PSScriptRoot 'fixtures/Get-MigrationTestCommand.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/migration/Invoke-Migration.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/migration/Set-Executed.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/shared/GenericSqlCleanup.ps1')
}

Describe 'Connection-string executor input' {
	BeforeEach {
		Mock Get-MigrationScriptConnection { throw 'Invalid or empty scripts must not allocate SQL resources.' }
		Mock Get-MigrationScriptCommand { throw 'Invalid or empty scripts must not allocate a command.' }
		Mock Get-MigrationSuppressionScope { throw 'Invalid or empty scripts must not allocate a scope.' }
		$script:inputPath = Join-Path $TestDrive 'input.sql'
		[System.IO.File]::WriteAllText($script:inputPath, '')
	}

	It 'requires only mandatory string ConnStr and Script inputs' {
		$metadata = Get-Command Invoke-Migration
		$metadata.Parameters.ContainsKey('SqlCmd') | Should -BeFalse
		foreach ($name in @('ConnStr', 'Script')) {
			$metadata.Parameters[$name].ParameterType | Should -Be ([string])
			$parameterAttributes = @($metadata.Parameters[$name].Attributes | Where-Object {
				$_ -is [System.Management.Automation.ParameterAttribute]
			})
			$parameterAttributes.Mandatory | Should -Contain $true
		}
	}

	It 'rejects <Kind> ConnStr during parameter binding (executable=<Executable>)' -ForEach @(
		foreach ($executable in @($false, $true)) {
			foreach ($entry in @(
				@{ Kind = 'null'; Value = $null }
				@{ Kind = 'empty'; Value = '' }
			)) {
				@{ Kind = $entry.Kind; Value = $entry.Value; Executable = $executable }
			}
		}
	) {
		if ($Executable) {
			[System.IO.File]::WriteAllText($script:inputPath, 'SELECT 1;')
		}
		$caught = $null
		try {
			Invoke-Migration -ConnStr $Value -Script $script:inputPath
		}
		catch {
			$caught = $_
		}
		$caught.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
		Should -Invoke Get-MigrationScriptConnection -Times 0 -Exactly
		Should -Invoke Get-MigrationScriptCommand -Times 0 -Exactly
		Should -Invoke Get-MigrationSuppressionScope -Times 0 -Exactly
	}

	It 'rejects <Kind> ConnStr locally without SQL allocation (executable=<Executable>)' -ForEach @(
		foreach ($executable in @($false, $true)) {
			foreach ($entry in @(
				@{ Kind = 'whitespace'; Value = '   ' }
				@{ Kind = 'malformed'; Value = 'Server="unterminated' }
				@{ Kind = 'unknown keyword'; Value = 'PrivateKeyword=private-value' }
				@{ Kind = 'invalid typed value'; Value = 'Server=unused;Connect Timeout=private-value' }
			)) {
				@{ Kind = $entry.Kind; Value = $entry.Value; Executable = $executable }
			}
		}
	) {
		if ($Executable) {
			[System.IO.File]::WriteAllText($script:inputPath, 'SELECT 1;')
		}
		$caught = $null
		try {
			Invoke-Migration -ConnStr $Value -Script $script:inputPath
		}
		catch {
			$caught = $_
		}
		$caught.Exception | Should -BeOfType ([System.ArgumentException])
		$caught.Exception.Message | Should -Match 'ConnStr|connection string'
		$caught.Exception.Message | Should -BeLike "*Migration '$script:inputPath':*"
		$caught.Exception.Message | Should -Not -Match 'private-value|unterminated|PrivateKeyword'
		if ($Kind -ne 'whitespace') {
			$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
		}
		Should -Invoke Get-MigrationScriptConnection -Times 0 -Exactly
		Should -Invoke Get-MigrationScriptCommand -Times 0 -Exactly
		Should -Invoke Get-MigrationSuppressionScope -Times 0 -Exactly
	}

	It 'validates ConnStr for a <Kind> script without probing the server or allocating SQL resources' -ForEach @(
		@{ Kind = 'empty'; Source = '' }
		@{ Kind = 'whitespace-only'; Source = " `t`r`n" }
		@{ Kind = 'comment-only'; Source = '-- no executable statements' }
	) {
		[System.IO.File]::WriteAllText($script:inputPath, $Source)
		@(Invoke-Migration -ConnStr 'Server=unreachable;Database=unused;User ID=synthetic;Password=synthetic' `
			-Script $script:inputPath) | Should -HaveCount 0
		Should -Invoke Get-MigrationScriptConnection -Times 0 -Exactly
		Should -Invoke Get-MigrationScriptCommand -Times 0 -Exactly
		Should -Invoke Get-MigrationSuppressionScope -Times 0 -Exactly
	}
}

Describe 'Borrowed history command contract' {
	It '<Helper> requires a typed SqlCmd and removes ConnStr' -ForEach @(@{ Helper = 'Set-Executed' }) {
		$metadata = Get-Command $Helper
		$metadata.Parameters.ContainsKey('ConnStr') | Should -BeFalse
		$metadata.Parameters['SqlCmd'].ParameterType | Should -Be ([Microsoft.Data.SqlClient.SqlCommand])
		$parameterAttributes = @($metadata.Parameters['SqlCmd'].Attributes | Where-Object {
			$_ -is [System.Management.Automation.ParameterAttribute]
		})
		$parameterAttributes.Mandatory | Should -Contain $true
	}

	It '<Helper> rejects <State> without allocating or opening resources' -ForEach @(
		foreach ($helper in @('Set-Executed')) {
			foreach ($state in @('null', 'missing connection', 'closed')) {
				@{ Helper = $helper; State = $state }
			}
		}
	) {
		$command = $null
		if ($State -ne 'null') {
			$command = [Microsoft.Data.SqlClient.SqlCommand]::new()
		}
		if ($State -eq 'closed') {
			$command.Connection = [Microsoft.Data.SqlClient.SqlConnection]::new()
		}
		$arguments = @{ SqlCmd = $command }
		$arguments += @{ ScriptName = 'one.sql'; Phase = 'test'; Checksum = ('a' * 64); ForceScript = $false }
		{ & $Helper @arguments } | Should -Throw '*SqlCmd*already open connection*'
		if ($State -eq 'closed') {
			$command.Connection.State | Should -Be 'Closed'
		}
	}

	It 'replaces operation state and binds typed history values on the same borrowed command' {
		$command = Get-MigrationTestCommand
		$connection = $command.Connection
		$null = $command.Parameters.AddWithValue('@stale', 'private-old-value')
		$command.CommandType = 'StoredProcedure'
		Set-Executed -SqlCmd $command -ScriptName 'Nested/new.sql' -HistoryScriptName 'NESTED\OLD.SQL' -Phase 'test' -Checksum ('a' * 64) -ForceScript $true
		$command.CommandType | Should -Be 'Text'
		$command.CommandText | Should -Match 'update dbo.fast1_migration_history'
		$command.CommandText | Should -Not -Match 'Nested/new.sql|NESTED\\OLD.SQL'
		$command.Parameters.Count | Should -Be 4
		foreach ($entry in @(
			@{ Name = '@script_name'; Type = 'NVarChar'; Size = 255; Value = 'Nested/new.sql' }
			@{ Name = '@history_script_name'; Type = 'NVarChar'; Size = 255; Value = 'NESTED\OLD.SQL' }
			@{ Name = '@phase'; Type = 'NVarChar'; Size = 32; Value = 'test' }
			@{ Name = '@checksum'; Type = 'Char'; Size = 64; Value = ('a' * 64) }
		)) {
			$parameter = $command.Parameters[$entry.Name]
			$parameter.SqlDbType.ToString() | Should -Be $entry.Type
			$parameter.Size | Should -Be $entry.Size
			$parameter.Value | Should -BeExactly $entry.Value
		}
		[object]::ReferenceEquals($command.Connection, $connection) | Should -BeTrue
		$command.CommandTimeout | Should -Be 73
		Set-Executed -SqlCmd $command -ScriptName 'next.sql' -Phase 'test' -Checksum ('b' * 64) -ForceScript $false
		$command.CommandText | Should -Match 'insert dbo.fast1_migration_history'
		$command.Parameters['@history_script_name'].Value | Should -BeExactly 'next.sql'
		$command.Observations | Should -HaveCount 2
		$connection.State | Should -Be 'Open'
	}

	It 'keeps a history failure safe and leaves borrowed resources available for reuse' {
		$command = Get-MigrationTestCommand
		$command.FailAt = 1
		$caught = $null
		try {
			Set-Executed -SqlCmd $command -ScriptName 'private-name.sql' -Phase 'test' -Checksum ('a' * 64) -ForceScript $false
		}
		catch {
			$caught = $_
		}
		$caught.Exception.Message | Should -Match 'history.*private-name.sql|private-name.sql.*history'
		$caught.Exception.Message | Should -Not -Match 'private SQL details'
		$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
		$command.Connection.State | Should -Be 'Open'
		$command.CommandTimeout | Should -Be 73
		Set-Executed -SqlCmd $command -ScriptName 'retry.sql' -Phase 'test' -Checksum ('b' * 64) -ForceScript $false
		$command.Observations | Should -HaveCount 2
	}
}

