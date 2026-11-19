BeforeAll {
	. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent $PSScriptRoot)
	. (Join-Path $PSScriptRoot 'fixtures/Get-MigrationTestCommand.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/migration/Invoke-Migration.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/shared/GenericSqlCleanup.ps1')
}

Describe 'Owned migration lifecycle (offline I/O interception)' {
	BeforeEach {
		$script:execution = Get-MigrationTestExecution
		$script:path = Join-Path $TestDrive 'session.sql'
		[System.IO.File]::WriteAllText($script:path, "BEGIN TRAN;`nGO`nCOMMIT;")
		Mock Get-MigrationScriptConnection {
			($ConnStr -ceq 'Server=unused; Database=configured_target;Application Name="original spelling"') | Should -BeTrue
			$script:execution.Events.Add('connection-create')
			$script:execution.Connection
		}
		Mock Get-MigrationScriptCommand {
			[object]::ReferenceEquals($Connection, $script:execution.Connection) | Should -BeTrue
			$script:execution.Events.Add('command-create')
			$script:execution.Command
		}
		$script:connStr = 'Server=unused; Database=configured_target;Application Name="original spelling"'
	}

	It 'owns one command/session at timeout zero for all batches and postflight' {
		Invoke-Migration -ConnStr $script:connStr -Script $script:path
		$command = $script:execution.Command
		$command.Observations | Should -HaveCount 2
		foreach ($observation in $command.Observations) {
			[object]::ReferenceEquals($observation.Connection, $script:execution.Connection) | Should -BeTrue
			$observation.Timeout | Should -Be 0
		}
		$command.Checks | Should -HaveCount 1
		$command.Checks[0].Text | Should -BeExactly 'SELECT @@TRANCOUNT;'
		$command.Checks[0].Timeout | Should -Be 0
		$command.Checks[0].ParameterCount | Should -Be 0
		$script:execution.Events.ToArray() | Should -Be @('connection-create', 'open', 'command-create', 'command-dispose', 'connection-dispose')
		Should -Invoke Get-MigrationScriptCommand -Times 1 -Exactly
	}

	It 'rejects nonzero or failed transaction completion (failure=<CheckFails>)' -ForEach @(
		@{ CheckFails = $false }
		@{ CheckFails = $true }
	) {
		$script:execution.Command.TransactionCount = 1
		$script:execution.Command.FailCheck = $CheckFails
		{ Invoke-Migration -ConnStr $script:connStr -Script $script:path } | Should -Throw '*transaction completion*'
		$script:execution.Events[-2..-1] | Should -Be @('command-dispose', 'connection-dispose')
	}

	It 'restores ambient context after <Outcome>' -ForEach @(
		@{ Outcome = 'success' }
		@{ Outcome = 'batch failure' }
	) {
		$ambient = [System.Transactions.TransactionScope]::new()
		try {
			$callerTransaction = [System.Transactions.Transaction]::Current
			if ($Outcome -eq 'batch failure') {
				$script:execution.Command.FailAt = 1
				{ Invoke-Migration -ConnStr $script:connStr -Script $script:path } | Should -Throw '*batch 1*'
			}
			else {
				Invoke-Migration -ConnStr $script:connStr -Script $script:path
			}
			$script:execution.Command.Observations[0].Ambient | Should -BeNullOrEmpty
			[object]::ReferenceEquals([System.Transactions.Transaction]::Current, $callerTransaction) | Should -BeTrue
			$ambient.Complete()
		}
		finally {
			$ambient.Dispose()
		}
	}

	It 'cleans up initialized resources when <Stage> fails' -ForEach @(
		@{ Stage = 'suppression' }
		@{ Stage = 'construction' }
		@{ Stage = 'open' }
		@{ Stage = 'command creation' }
	) {
		switch ($Stage) {
			'suppression' {
				Mock Get-MigrationSuppressionScope { throw 'private suppression details' }
			}
			'construction' {
				Mock Get-MigrationScriptConnection { throw 'private construction details' }
			}
			'open' {
				$script:execution.FailOpen = $true
			}
			'command creation' {
				Mock Get-MigrationScriptCommand { throw 'private command details' }
			}
		}
		$caught = $null
		try {
			Invoke-Migration -ConnStr $script:connStr -Script $script:path
		}
		catch {
			$caught = $_
		}
		$caught.Exception.Message | Should -Match 'session.sql.*failed'
		$caught.Exception.Message | Should -Not -Match 'private .* details|original spelling|Server='
		$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
		$script:execution.Command.Observations | Should -HaveCount 0
		if ($Stage -in @('open', 'command creation')) {
			$script:execution.Events[-1] | Should -Be 'connection-dispose'
		}
		else {
			$script:execution.Events | Should -HaveCount 0
		}
	}
}

Describe 'Original migration batches (offline command interception)' {
	BeforeEach {
		$script:execution = Get-MigrationTestExecution
		Mock Get-MigrationScriptConnection { $script:execution.Connection }
		Mock Get-MigrationScriptCommand { $script:execution.Command }
	}
	It 'executes source in order once, ignoring empty boundaries and quoted/commented GO' {
		$source = "GO`r`nSELECT 'first`r`nGO`r`nlast'; /* GO */`r`ngO`r`nGO`r`n/* before */ SELECT 2; -- after`r`nGO`r`n"
		$path = Join-Path $TestDrive 'literal[1].sql'
		[System.IO.File]::WriteAllText($path, $source)
		$command = $script:execution.Command
		try {
			$null = $command.Parameters.AddWithValue('@stale', 'old')
			$result = @(Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $path)
			$result | Should -HaveCount 0
			$command.Observations | Should -HaveCount 2
			$command.Observations[0].Text | Should -BeExactly "SELECT 'first`r`nGO`r`nlast';"
			$command.Observations[1].Text | Should -BeExactly 'SELECT 2;'
			$command.Parameters.Count | Should -Be 0
			$command.CommandTimeout | Should -Be 0
			$command.CommandType | Should -Be 'Text'
		}
		finally {
			$command.Dispose()
			$command.Connection.Dispose()
		}
	}

	It 'preserves a batch-scoped definition and multiline comments verbatim' {
		$source = "CREATE PROCEDURE dbo.example AS`nBEGIN`n/* multi`nGO`ncomment */`nSELECT 1;`nEND;`nGO`nEXEC dbo.example;"
		$path = Join-Path $TestDrive 'definition.sql'
		[System.IO.File]::WriteAllText($path, $source)
		$command = $script:execution.Command
		Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $path
		$command.Observations | Should -HaveCount 2
		$command.Observations[0].Text | Should -BeExactly $source.Substring(0, $source.IndexOf("`nGO`nEXEC"))
		$command.Observations[1].Text | Should -BeExactly 'EXEC dbo.example;'
	}

	It 'succeeds with no SQL for <Kind>' -ForEach @(
		@{ Kind = 'empty'; Source = '' }
		@{ Kind = 'whitespace'; Source = " `r`n`t" }
		@{ Kind = 'comments'; Source = "-- comment`n/* GO */" }
		@{ Kind = 'separators'; Source = "GO`ngo`n-- gap`nGO" }
	) {
		$path = Join-Path $TestDrive 'empty.sql'
		[System.IO.File]::WriteAllText($path, $Source)
		$command = $script:execution.Command
		$command.CommandType = 'StoredProcedure'
		$command.CommandText = 'old_operation'
		$null = $command.Parameters.AddWithValue('@stale', 'old')
		@(Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $path) | Should -HaveCount 0
		$command.Observations | Should -HaveCount 0
		$command.Parameters.Count | Should -Be 1
		$command.CommandType | Should -Be 'StoredProcedure'
		$command.CommandText | Should -BeExactly 'old_operation'
		$command.Checks | Should -HaveCount 0
		Should -Invoke Get-MigrationScriptConnection -Times 0 -Exactly
		Should -Invoke Get-MigrationScriptCommand -Times 0 -Exactly
	}

	It 'stops on a later runtime failure and preserves cause with original batch coordinates' {
		$path = Join-Path $TestDrive 'runtime.sql'
		[System.IO.File]::WriteAllText($path, "SELECT 1;`nGO`n`nSELECT 2;`nGO`nSELECT 3;")
		$command = $script:execution.Command
		$command.FailAt = 2
		$caught = $null
		try {
			Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $path
		}
		catch {
			$caught = $_
		}
		$caught.Exception.Message | Should -Match 'runtime.sql.*batch 2.*line 4.*column 1'
		$caught.Exception.Message | Should -Not -Match 'private SQL details|SELECT'
		$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
		$command.Observations | Should -HaveCount 2
		$command.Connection.State | Should -Be 'Open'
		$command.CommandTimeout | Should -Be 0
	}
}

