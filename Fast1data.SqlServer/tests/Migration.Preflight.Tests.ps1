BeforeAll {
	. (Join-Path $PSScriptRoot 'fixtures/Import-SharedHelperDependency.ps1') -DistributionRoot (Split-Path -Parent $PSScriptRoot)
	. (Join-Path $PSScriptRoot 'fixtures/Get-MigrationTestCommand.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/migration/Invoke-Migration.ps1')
	. (Join-Path (Split-Path -Parent $PSScriptRoot) 'private/shared/GenericSqlCleanup.ps1')
}

Describe 'Whole-file migration validation' {
	BeforeEach {
		$script:execution = Get-MigrationTestExecution
		Mock Get-MigrationScriptConnection { $script:execution.Connection }
		Mock Get-MigrationScriptCommand { $script:execution.Command }
	}
	It 'rejects <Kind> before any command with safe original coordinates' -ForEach @(
		@{ Kind = 'later syntax'; Tail = 'SELECT FROM;'; Diagnostic = 'parse.*line 3.*column' }
		@{ Kind = 'lexical'; Tail = "SELECT 'unclosed"; Diagnostic = '(lexical|parse).*line 3.*column' }
		@{ Kind = 'GO 1'; Tail = "SELECT 2;`nGO 1"; Diagnostic = 'counted GO.*line 4.*column 1' }
		@{ Kind = 'GO 3'; Tail = "SELECT 2;`nGO 3"; Diagnostic = 'counted GO.*line 4.*column 1' }
		@{ Kind = 'include'; Tail = ':r private-file.sql'; Diagnostic = 'directive.*line 3.*column 1' }
		@{ Kind = 'setvar'; Tail = ':setvar PrivateName PrivateValue'; Diagnostic = 'directive.*line 3.*column 1' }
		@{ Kind = 'connect'; Tail = ':connect private-host'; Diagnostic = 'directive.*line 3.*column 1' }
		@{ Kind = 'shell'; Tail = '!! private-command'; Diagnostic = 'directive.*line 3.*column 1' }
		@{ Kind = 'utility'; Tail = 'QUIT'; Diagnostic = 'directive.*line 3.*column 1' }
		@{ Kind = 'quoted substitution'; Tail = "SELECT '`$(PrivateName)';"; Diagnostic = 'substitution.*line 3.*column 9' }
		@{ Kind = 'identifier substitution'; Tail = 'SELECT [$(PrivateName)];'; Diagnostic = 'substitution.*line 3.*column 9' }
		@{ Kind = 'comment substitution'; Tail = '-- $(PrivateName)'; Diagnostic = 'substitution.*line 3.*column 4' }
	) {
		$path = Join-Path $TestDrive 'preflight.sql'
		[System.IO.File]::WriteAllText($path, "SELECT 1;`nGO`n$Tail")
		$command = $script:execution.Command
		$caught = $null
		try {
			Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $path
		}
		catch {
			$caught = $_
		}
		$caught | Should -Not -BeNullOrEmpty
		$caught.Exception.Message | Should -Match $Diagnostic
		$caught.Exception.Message | Should -Not -Match 'PrivateName|PrivateValue|private-host|private-file|SELECT|unclosed'
		$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
		$command.Observations | Should -HaveCount 0
		Should -Invoke Get-MigrationScriptConnection -Times 0 -Exactly
	}

	It 'allows directive/count mentions inside multiline literals, comments and identifiers' {
		$source = "SELECT 'text`n:r example`nGO 3`n!! cmd`nQUIT';`n/*`n:connect host`nGO 1`n*/`nSELECT [GO 3] = 1;"
		$path = Join-Path $TestDrive 'mentions.sql'
		[System.IO.File]::WriteAllText($path, $source)
		$command = $script:execution.Command
		Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script $path
		$command.Observations | Should -HaveCount 1
		$command.Observations[0].Text | Should -BeExactly $source
	}

	It 'preserves the read failure as a cause without executing SQL' {
		$command = $script:execution.Command
		$caught = $null
		try {
			Invoke-Migration -ConnStr 'Server=unused;Database=configured_target' -Script (Join-Path $TestDrive 'missing.sql')
		}
		catch {
			$caught = $_
		}
		$caught.Exception.Message | Should -Match 'missing.sql.*read'
		$caught.Exception.InnerException | Should -Not -BeNullOrEmpty
		$command.Observations | Should -HaveCount 0
	}
}
