BeforeAll {
	$moduleRoot = Split-Path -Parent $PSScriptRoot
	. "$moduleRoot/private/shared/Get-FileChecksum.ps1"
	. "$moduleRoot/private/shared/Get-RelativePath.ps1"
	. "$moduleRoot/private/migration/Resolve-MigrationPhase.ps1"

	function New-PhaseFixture {
		[CmdletBinding(SupportsShouldProcess)]
		[OutputType([hashtable])]
		param (
			[string[]]$Scripts = @(),
			[string]$Phase = 'phase[01]'
		)
		$base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
		$directory = Join-Path $base $Phase
		if ($PSCmdlet.ShouldProcess($directory, 'Create migration test fixture')) {
			$null = [System.IO.Directory]::CreateDirectory($directory)
			foreach ($name in $Scripts) {
				$path = Join-Path $directory $name.Replace('\', '/')
				$null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
				Set-Content -LiteralPath $path -Value "-- $name"
			}
			$config = [ordered]@{}
			$config[$Phase] = @{ scripts = @($Scripts) }
			$config['other'] = @{ scripts = @('not-created.sql') }
			$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $base 'migration.json')
		}
		@{ BasePath = $base; Phase = $Phase; History = @() }
	}
}

Describe 'Migration phase containment and complete evaluation' {
	It 'rejects a late <Invalid> entry without emitting partial results' -ForEach @(
		@{ Invalid = 'parent'; Message = '*outside the phase directory*' }
		@{ Invalid = 'absolute'; Message = '*outside the phase directory*' }
		@{ Invalid = 'sibling-prefix'; Message = '*outside the phase directory*' }
		@{ Invalid = 'directory'; Message = '*outside the phase directory*' }
		@{ Invalid = 'ignored-escape'; Message = '*outside the phase directory*' }
		@{ Invalid = 'forced-escape'; Message = '*outside the phase directory*' }
		@{ Invalid = 'missing'; Message = '*script not found*' }
		@{ Invalid = 'forced-missing'; Message = '*script not found*' }
		@{ Invalid = 'duplicate'; Message = '*Duplicate*' }
		@{ Invalid = 'conflict'; Message = '*both ignored and forced*' }
		@{ Invalid = 'drift'; Message = '*Checksum mismatch*' }
	) {
		$fixture = New-PhaseFixture -Scripts 'first.sql', 'last.sql'
		$phaseDirectory = Join-Path $fixture.BasePath $fixture.Phase
		$late = 'last.sql'
		$selection = @{}
		switch ($Invalid) {
			'parent' {
				$late = '../outside.sql'
				Set-Content -LiteralPath (Join-Path $fixture.BasePath 'outside.sql') -Value '-- outside'
			}
			'absolute' {
				$late = Join-Path $fixture.BasePath 'outside.sql'
				Set-Content -LiteralPath $late -Value '-- outside'
			}
			'sibling-prefix' {
				$late = "../$($fixture.Phase)-other/outside.sql"
				$null = [System.IO.Directory]::CreateDirectory("$phaseDirectory-other")
				Set-Content -LiteralPath "$phaseDirectory-other/outside.sql" -Value '-- outside'
			}
			'directory' {
				$late = $phaseDirectory
			}
			'ignored-escape' {
				$late = '../outside.sql'
				$selection.IgnoreScripts = @($late)
			}
			'forced-escape' {
				$late = '../outside.sql'
				$selection.ForceScripts = @($late)
			}
			'missing' {
				$late = 'missing.sql'
			}
			'forced-missing' {
				$late = 'missing.sql'
				$selection.ForceScripts = @($late)
			}
			'duplicate' {
				$late = 'FIRST.SQL'
			}
			'conflict' {
				$selection.IgnoreScripts = @('LAST.SQL')
				$selection.ForceScripts = @('last.sql')
			}
			'drift' {
				$fixture.History = @([PSCustomObject]@{ script_name = 'LAST.SQL'; checksum = 'old' })
			}
		}
		$config = @{}
		$config[$fixture.Phase] = @{ scripts = @('first.sql', $late) }
		$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
		$received = [System.Collections.Generic.List[object]]::new()
		{ Resolve-MigrationPhase @fixture @selection | ForEach-Object { $received.Add($_) } } | Should -Throw $Message
		$received.Count | Should -Be 0
	}

	It 'ignores contained missing and drifted files without hashing them' {
		$fixture = New-PhaseFixture -Scripts 'changed.sql'
		$config = @{}
		$config[$fixture.Phase] = @{ scripts = @('missing.sql', 'changed.sql') }
		$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
		$fixture.History = @([PSCustomObject]@{ script_name = 'changed.sql'; checksum = 'old' })
		Mock Get-FileChecksum { throw 'Ignored scripts must never be hashed.' }
		$result = Resolve-MigrationPhase @fixture -IgnoreScripts 'missing.sql', 'changed.sql'
		$result.Scripts.Reason | Should -Be @('Ignored', 'Ignored')
		Should -Invoke Get-FileChecksum -Times 0 -Exactly
	}

	It 'uses host filesystem rules without lowercasing file lookup' {
		$fixture = New-PhaseFixture -Scripts 'Case.sql'
		$path = Join-Path $fixture.BasePath "$($fixture.Phase)/Case.sql"
		$result = Resolve-MigrationPhase @fixture
		$result.Scripts[0].FullPath | Should -BeExactly $path
		if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $path) 'case.sql'))) {
			$config = @{}
			$config[$fixture.Phase] = @{ scripts = @('case.sql') }
			$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
			{ Resolve-MigrationPhase @fixture } | Should -Throw '*script not found*'
		}
	}

	It 'rejects differently cased sibling directories on a case-sensitive filesystem' {
		if ($IsWindows) {
			Set-ItResult -Skipped -Because 'Requires a Unix case-sensitive filesystem.'
			return
		}
		$fixture = New-PhaseFixture -Phase 'Phase' -Scripts 'one.sql'
		$other = Join-Path $fixture.BasePath 'phase'
		if (Test-Path -LiteralPath $other) {
			Set-ItResult -Skipped -Because 'This filesystem is case-insensitive.'
			return
		}
		$null = [System.IO.Directory]::CreateDirectory($other)
		Set-Content -LiteralPath "$other/escape.sql" -Value '-- outside'
		@{ Phase = @{ scripts = @('one.sql', '../phase/escape.sql') } } | ConvertTo-Json -Depth 5 |
			Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
		{ Resolve-MigrationPhase @fixture } | Should -Throw '*outside the phase directory*'
	}
}

Describe 'Migration phase identity and decisions' {
	It 'resolves a relative BasePath from the PowerShell location' {
		$fixture = New-PhaseFixture -Scripts 'one.sql'
		$basePath = $fixture.BasePath
		try {
			Push-Location -LiteralPath $basePath
			$fixture.BasePath = '.'
			$result = Resolve-MigrationPhase @fixture
			$result.ConfigFile | Should -BeExactly (Join-Path $basePath 'migration.json')
			$result.Scripts[0].ScriptName | Should -BeExactly 'one.sql'
		}
		finally {
			Pop-Location
		}
	}

	It 'selects literal bracketed names and preserves nonalphabetical nested order and casing' {
		$fixture = New-PhaseFixture -Scripts 'z[1].sql', 'Nested/A.sql', 'b.sql'
		$result = Resolve-MigrationPhase @fixture
		$result.Phase | Should -BeExactly 'phase[01]'
		$result.ConfigFile | Should -BeExactly (Join-Path $fixture.BasePath 'migration.json')
		$result.PhaseDirectory | Should -BeExactly (Join-Path $fixture.BasePath $fixture.Phase)
		$result.Scripts.ScriptName | Should -Be @('z[1].sql', 'Nested/A.sql', 'b.sql')
		$result.Scripts[1].FullPath | Should -BeExactly (Join-Path $result.PhaseDirectory 'Nested/A.sql')
		$result.Scripts[0].Checksum | Should -Be (Get-FileHash -LiteralPath $result.Scripts[0].FullPath).Hash
	}

	It 'returns explicit decision and warning arrays for <Count> scripts' -ForEach @(
		@{ Count = 0; Names = @() }
		@{ Count = 1; Names = @('one.sql') }
		@{ Count = 2; Names = @('two.sql', 'one.sql') }
	) {
		$fixture = New-PhaseFixture -Scripts $Names
		$result = Resolve-MigrationPhase @fixture
		$result.Scripts -is [array] | Should -BeTrue
		$result.Warnings -is [array] | Should -BeTrue
		$result.Scripts.Count | Should -Be $Count
		$result.Warnings.Count | Should -Be 0
	}

	It 'distinguishes missing phase, configuration, and directory from empty work' -ForEach @(
		@{ Missing = 'phase'; Message = '*Migration phase not found*' }
		@{ Missing = 'configuration'; Message = '*configuration not found*' }
		@{ Missing = 'directory'; Message = '*phase directory not found*' }
	) {
		$fixture = New-PhaseFixture
		switch ($Missing) {
			'phase' {
				$fixture.Phase = 'absent'
			}
			'configuration' {
				Remove-Item -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
			}
			'directory' {
				Remove-Item -LiteralPath (Join-Path $fixture.BasePath $fixture.Phase)
			}
		}
		{ Resolve-MigrationPhase @fixture } | Should -Throw $Message
	}

	It 'matches case and both separators across history, ignore, and force with exact original keys' {
		$fixture = New-PhaseFixture -Scripts 'Nested\Old.sql', 'Nested/Ignore.sql', 'Nested/Force.sql', 'New.sql'
		$fixture.History = @(
			[PSCustomObject]@{ script_name = 'NESTED\OLD.SQL'; checksum = (Get-FileChecksum (Join-Path $fixture.BasePath "$($fixture.Phase)/Nested/Old.sql")) }
			[PSCustomObject]@{ script_name = 'nested\FORCE.sql'; checksum = 'old-checksum' }
			[PSCustomObject]@{ script_name = 'history-only.sql'; checksum = 'unconfigured' }
		)
		$result = Resolve-MigrationPhase @fixture -IgnoreScripts 'NESTED\IGNORE.SQL' -ForceScripts 'NESTED\force.SQL'
		$result.Scripts.ScriptName | Should -Be @('Nested/Old.sql', 'Nested/Ignore.sql', 'Nested/Force.sql', 'New.sql')
		$result.Scripts.Action | Should -Be @('Skip', 'Skip', 'Run', 'Run')
		$result.Scripts.Reason | Should -Be @('AlreadyExecuted', 'Ignored', 'Forced', 'New')
		$result.Scripts[0].HistoryScriptName | Should -BeExactly 'NESTED\OLD.SQL'
		$result.Scripts[2].HistoryScriptName | Should -BeExactly 'nested\FORCE.sql'
		$result.Scripts[1].Checksum | Should -BeNullOrEmpty
		$result.Scripts[3].HistoryScriptName | Should -BeNullOrEmpty
		$result.Scripts[2].WasExecuted | Should -BeTrue
		$result.Scripts[2].IsForced | Should -BeTrue
		$result.Scripts[3].WasExecuted | Should -BeFalse
		$result.Warnings.Count | Should -Be 0
	}

	It 'forces a new script without pretending it was executed before' {
		$fixture = New-PhaseFixture -Scripts 'New.sql'
		$script = (Resolve-MigrationPhase @fixture -ForceScripts 'NEW.SQL').Scripts[0]
		$script.Action | Should -Be 'Run'
		$script.Reason | Should -Be 'Forced'
		$script.WasExecuted | Should -BeFalse
		$script.HistoryScriptName | Should -BeNullOrEmpty
	}

	It 'rejects normalized configured duplicates before file eligibility' {
		$fixture = New-PhaseFixture -Scripts 'Nested/one.sql'
		@{ 'phase[01]' = @{ scripts = @('Nested/one.sql', 'NESTED\ONE.SQL') } } |
			ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
		{ Resolve-MigrationPhase @fixture } | Should -Throw '*Duplicate*NESTED/ONE.SQL*'
	}

	It 'rejects even unknown global ignore/force conflicts' {
		$fixture = New-PhaseFixture
		{ Resolve-MigrationPhase @fixture -IgnoreScripts 'Missing\One.sql' -ForceScripts 'MISSING/ONE.SQL' } |
			Should -Throw '*both ignored and forced*'
	}

	It 'returns distinct ordered unknown-selection warnings without extra work' {
		$fixture = New-PhaseFixture -Scripts 'one.sql'
		$result = Resolve-MigrationPhase @fixture -IgnoreScripts 'absent1.sql', 'absent2.sql' -ForceScripts 'absent3.sql'
		$result.Scripts.Count | Should -Be 1
		$result.Warnings -is [array] | Should -BeTrue
		$result.Warnings.Count | Should -Be 3
		$result.Warnings[0] | Should -BeLike '*IgnoreScripts*absent1.sql*'
		$result.Warnings[1] | Should -BeLike '*IgnoreScripts*absent2.sql*'
		$result.Warnings[2] | Should -BeLike '*ForceScripts*absent3.sql*'
		(Resolve-MigrationPhase @fixture -IgnoreScripts 'absent.sql').Warnings.Count | Should -Be 1
	}

	It 'converts contained rooted names from <Source> to phase-relative identity' -ForEach @(
		@{ Source = 'configuration' }
		@{ Source = 'history' }
		@{ Source = 'ignore' }
		@{ Source = 'force' }
	) {
		$fixture = New-PhaseFixture -Scripts 'Nested/one.sql'
		$absolute = Join-Path $fixture.BasePath "$($fixture.Phase)/Nested/one.sql"
		$selection = @{}
		switch ($Source) {
			'configuration' {
				@{ 'phase[01]' = @{ scripts = @($absolute) } } | ConvertTo-Json -Depth 5 |
					Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
			}
			'history' {
				$fixture.History = @([PSCustomObject]@{ script_name = $absolute; checksum = (Get-FileChecksum $absolute) })
			}
			'ignore' {
				$selection.IgnoreScripts = @($absolute)
			}
			'force' {
				$selection.ForceScripts = @($absolute)
			}
		}
		$result = Resolve-MigrationPhase @fixture @selection
		$result.Scripts[0].ScriptName | Should -BeExactly 'Nested/one.sql'
		$result.Warnings.Count | Should -Be 0
		if ($Source -eq 'history') {
			$result.Scripts[0].HistoryScriptName | Should -BeExactly $absolute
			$result.Scripts[0].Reason | Should -Be 'AlreadyExecuted'
		}
		if ($Source -eq 'ignore') {
			$result.Scripts[0].Reason | Should -Be 'Ignored'
		}
		if ($Source -eq 'force') {
			$result.Scripts[0].Reason | Should -Be 'Forced'
		}
	}

	It 'preserves relative spelling rather than deduplicating general path aliases' {
		$fixture = New-PhaseFixture -Scripts 'one.sql'
		@{ 'phase[01]' = @{ scripts = @('one.sql', './one.sql') } } | ConvertTo-Json -Depth 5 |
			Set-Content -LiteralPath (Join-Path $fixture.BasePath 'migration.json')
		(Resolve-MigrationPhase @fixture).Scripts.ScriptName | Should -Be @('one.sql', './one.sql')
	}

	It 'rejects unforced checksum drift with identity and expected/current checksums' {
		$fixture = New-PhaseFixture -Scripts 'one.sql'
		$checksum = Get-FileChecksum (Join-Path $fixture.BasePath "$($fixture.Phase)/one.sql")
		$fixture.History = @([PSCustomObject]@{ script_name = 'ONE.SQL'; checksum = 'expected-value' })
		{ Resolve-MigrationPhase @fixture } | Should -Throw "*one.sql*Expected: expected-value*Current: $checksum*"
	}

	It 'reads configuration once and hashes every non-ignored script once, including skips' {
		$fixture = New-PhaseFixture -Scripts 'one.sql', 'two.sql', 'ignored.sql'
		$fixture.History = @([PSCustomObject]@{
			script_name = 'one.sql'
			checksum = (Get-FileChecksum (Join-Path $fixture.BasePath "$($fixture.Phase)/one.sql"))
		})
		Mock Get-FileChecksum { (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash }
		Mock Get-Content { [System.IO.File]::ReadAllText($LiteralPath) }
		$result = Resolve-MigrationPhase @fixture -IgnoreScripts 'ignored.sql'
		$result.Scripts.Count | Should -Be 3
		Should -Invoke Get-Content -Times 1 -Exactly
		Should -Invoke Get-FileChecksum -Times 2 -Exactly
		Should -Invoke Get-FileChecksum -Times 1 -Exactly -ParameterFilter { $File.EndsWith('one.sql') }
		Should -Invoke Get-FileChecksum -Times 1 -Exactly -ParameterFilter { $File.EndsWith('two.sql') }
		Should -Invoke Get-FileChecksum -Times 0 -Exactly -ParameterFilter { $File.EndsWith('ignored.sql') }
	}
}
