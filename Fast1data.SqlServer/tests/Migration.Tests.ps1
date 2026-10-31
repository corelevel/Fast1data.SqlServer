BeforeAll {
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force

	function New-CommandFixture {
		[CmdletBinding(SupportsShouldProcess)]
		param ([string[]]$Scripts = @('first.sql', 'last.sql'))
		$base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
		$directory = Join-Path $base 'phase01'
		if ($PSCmdlet.ShouldProcess($directory, 'Create migration command fixture')) {
			$null = [System.IO.Directory]::CreateDirectory($directory)
			foreach ($name in $Scripts) {
				$path = Join-Path $directory $name
				$null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
				Set-Content -LiteralPath $path -Value "-- $name"
			}
			@{ 'phase01' = @{ scripts = @($Scripts) } } | ConvertTo-Json -Depth 5 |
				Set-Content -LiteralPath (Join-Path $base 'migration.json')
		}
		$base
	}
}

Describe 'Migration validation' {
	It 'rejects scripts outside the selected phase directory' {
		$basePath = Join-Path $TestDrive 'traversal'
		$phasePath = Join-Path $basePath 'phase01'
		$null = New-Item -Path $phasePath -ItemType Directory -Force
		$null = New-Item -Path (Join-Path $basePath 'outside.sql') -ItemType File
		'{"phase01":{"scripts":["../outside.sql"]}}' |
			Set-Content -LiteralPath (Join-Path $basePath 'migration.json')

		InModuleScope 'Fast1data.SqlServer' -Parameters @{
			BasePath = $basePath
		} {
			Mock Get-Executed { @() }

			{
				Invoke-Fast1Migration `
					-ConnStr 'Data Source=(local);Initial Catalog=pester' `
					-BasePath $BasePath `
					-Phase 'phase01' `
					-WhatIf `
					-ErrorAction SilentlyContinue
			} | Should -Throw '*outside the phase directory*'
		}
	}

	It 'rejects scripts that are both ignored and forced' {
		$basePath = Join-Path $TestDrive 'intersection'
		$phasePath = Join-Path $basePath 'phase01'
		$null = New-Item -Path $phasePath -ItemType Directory -Force
		$null = New-Item -Path (Join-Path $phasePath 'Script.sql') -ItemType File
		'{"phase01":{"scripts":["Script.sql"]}}' |
			Set-Content -LiteralPath (Join-Path $basePath 'migration.json')

		InModuleScope 'Fast1data.SqlServer' -Parameters @{
			BasePath = $basePath
		} {
			Mock Get-Executed { @() }

			{
				Invoke-Fast1Migration `
					-ConnStr 'Data Source=(local);Initial Catalog=pester' `
					-BasePath $BasePath `
					-Phase 'phase01' `
					-IgnoreScripts 'script.sql' `
					-ForceScripts 'SCRIPT.SQL' `
					-WhatIf `
					-ErrorAction SilentlyContinue
			} | Should -Throw '*both ignored and forced*'
		}
	}
}

Describe 'Whole-phase command guards' {
	It 'rejects <Invalid> before mutation (WhatIf=<Preview>)' -ForEach @(
		foreach ($preview in @($false, $true)) {
			foreach ($invalid in @('configuration', 'phase', 'directory', 'duplicate', 'conflict', 'unknown-conflict', 'parent', 'absolute', 'sibling-prefix', 'self', 'ignored-escape', 'forced-escape', 'missing', 'forced-missing', 'drift')) {
				@{ Preview = $preview; Invalid = $invalid }
			}
		}
	) {
		$basePath = New-CommandFixture
		InModuleScope 'Fast1data.SqlServer' -Parameters @{ BasePath = $basePath; Preview = $Preview; Invalid = $Invalid } {
			$script:guardHistory = @()
			Mock Get-Executed { $script:guardHistory }
			Mock Invoke-Migration {}
			Mock Set-Executed {}
			$phaseDirectory = Join-Path $BasePath 'phase01'
			$late = 'last.sql'
			$selection = @{}
			$message = '*outside the phase directory*'
			switch ($Invalid) {
				'configuration' {
					$message = '*configuration not found*'
				}
				'phase' {
					$message = '*phase not found*'
				}
				'directory' {
					$message = '*phase directory not found*'
				}
				'duplicate' {
					$late = 'FIRST.SQL'
					$message = '*Duplicate*'
				}
				'conflict' {
					$selection.IgnoreScripts = @('LAST.SQL')
					$selection.ForceScripts = @('last.sql')
					$message = '*both ignored and forced*'
				}
				'unknown-conflict' {
					$selection.IgnoreScripts = @('unknown\NAME.sql')
					$selection.ForceScripts = @('UNKNOWN/name.sql')
					$message = '*both ignored and forced*'
				}
				'parent' {
					$late = '../outside.sql'
					Set-Content -LiteralPath (Join-Path $BasePath 'outside.sql') -Value '-- outside'
				}
				'absolute' {
					$late = Join-Path $BasePath 'outside.sql'
					Set-Content -LiteralPath $late -Value '-- outside'
				}
				'sibling-prefix' {
					$late = '../phase01-other/outside.sql'
					$null = [System.IO.Directory]::CreateDirectory("$phaseDirectory-other")
					Set-Content -LiteralPath "$phaseDirectory-other/outside.sql" -Value '-- outside'
				}
				'self' {
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
					$message = '*script not found*'
				}
				'forced-missing' {
					$late = 'missing.sql'
					$selection.ForceScripts = @($late)
					$message = '*script not found*'
				}
				'drift' {
					$script:guardHistory = @([PSCustomObject]@{ script_name = 'LAST.SQL'; checksum = 'expected' })
					$message = '*Checksum mismatch*'
				}
			}
			@{ 'phase01' = @{ scripts = @('first.sql', $late) } } | ConvertTo-Json -Depth 5 |
				Set-Content -LiteralPath (Join-Path $BasePath 'migration.json')
			switch ($Invalid) {
				'configuration' {
					Remove-Item -LiteralPath (Join-Path $BasePath 'migration.json')
				}
				'phase' {
					'{}' | Set-Content -LiteralPath (Join-Path $BasePath 'migration.json')
				}
				'directory' {
					# Rename only this fixture directory; keep all operations within TestDrive.
					Rename-Item -LiteralPath $phaseDirectory -NewName 'other'
				}
			}
			{
				Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath `
					-Phase 'phase01' @selection -WhatIf:$Preview -Confirm:$false -ErrorAction Stop
			} | Should -Throw $message
			Should -Invoke Invoke-Migration -Times 0 -Exactly
			Should -Invoke Set-Executed -Times 0 -Exactly
		}
	}
}

Describe 'Migration preview contract' {
	It 'performs reads and validation but no mutations when confirmation is declined' {
		if (-not ('Fast1MigrationDecliningHost' -as [type])) {
			Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
public sealed class Fast1MigrationDecliningHost : PSHost {
	private readonly Fast1MigrationDecliningUI ui = new Fast1MigrationDecliningUI();
	public int Choices => ui.Choices;
	public override string Name => "Migration confirmation test";
	public override Version Version => new Version(1, 0);
	public override Guid InstanceId { get; } = Guid.NewGuid();
	public override PSHostUserInterface UI => ui;
	public override CultureInfo CurrentCulture => CultureInfo.InvariantCulture;
	public override CultureInfo CurrentUICulture => CultureInfo.InvariantCulture;
	public override void SetShouldExit(int code) { }
	public override void EnterNestedPrompt() => throw new NotSupportedException();
	public override void ExitNestedPrompt() => throw new NotSupportedException();
	public override void NotifyBeginApplication() { }
	public override void NotifyEndApplication() { }
}
public sealed class Fast1MigrationDecliningUI : PSHostUserInterface {
	public int Choices;
	public override PSHostRawUserInterface RawUI => null;
	public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
		Choices++;
		for (int i = 0; i < choices.Count; i++) {
			if (choices[i].Label.Replace("&", "") == "No") {
				return i;
			}
		}
		throw new InvalidOperationException("No decline choice offered");
	}
	public override string ReadLine() => throw new NotSupportedException();
	public override SecureString ReadLineAsSecureString() => throw new NotSupportedException();
	public override Dictionary<string, PSObject> Prompt(string c, string m, Collection<FieldDescription> d) => throw new NotSupportedException();
	public override PSCredential PromptForCredential(string c, string m, string u, string t) => throw new NotSupportedException();
	public override PSCredential PromptForCredential(string c, string m, string u, string t, PSCredentialTypes a, PSCredentialUIOptions b) => throw new NotSupportedException();
	public override void Write(string value) { }
	public override void Write(ConsoleColor f, ConsoleColor b, string value) { }
	public override void WriteLine(string value) { }
	public override void WriteDebugLine(string value) { }
	public override void WriteVerboseLine(string value) { }
	public override void WriteWarningLine(string value) { }
	public override void WriteErrorLine(string value) { }
	public override void WriteProgress(long sourceId, ProgressRecord record) { }
}
'@
		}
		$basePath = New-CommandFixture
		$decliningHost = [Fast1MigrationDecliningHost]::new()
		$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($decliningHost)
		$pipeline = [powershell]::Create()
		try {
			$runspace.Open()
			$pipeline.Runspace = $runspace
			$null = $pipeline.AddScript({
				param ($ModulePath, $BasePath)
				Import-Module $ModulePath -Force
				& (Get-Module Fast1data.SqlServer) {
					$script:declineTrace = [System.Collections.Generic.List[string]]::new()
					function script:Get-Executed {
						$script:declineTrace.Add('read')
					}
					function script:Invoke-Migration {
						$script:declineTrace.Add('execute')
					}
					function script:Set-Executed {
						$script:declineTrace.Add('write')
					}
				}
				Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath -Phase 'phase01' -Confirm
				& (Get-Module Fast1data.SqlServer) { $script:declineTrace.ToArray() }
			}.ToString()).AddArgument((Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1')).AddArgument($basePath)
			$trace = @($pipeline.Invoke() | ForEach-Object { "$_" })
			$pipeline.Streams.Error.Count | Should -Be 0
			$decliningHost.Choices | Should -Be 1
			$trace | Should -Be @('read')
		}
		finally {
			$pipeline.Dispose()
			$runspace.Dispose()
		}
	}

	It 'reports identical ordered decisions and warnings for execution and WhatIf, including force' {
		$basePath = New-CommandFixture -Scripts 'z[1].sql', 'Nested/Old.sql', 'ignored.sql', 'Nested/Force.sql', 'ForcedNew.sql'
		InModuleScope 'Fast1data.SqlServer' -Parameters @{ BasePath = $basePath } {
			$script:previewHistory = @(
				[PSCustomObject]@{ script_name = 'NESTED\OLD.SQL'; checksum = (Get-FileChecksum (Join-Path $BasePath 'phase01/Nested/Old.sql')) }
				[PSCustomObject]@{ script_name = 'nested\force.SQL'; checksum = 'old' }
			)
			Mock Get-Executed { $script:previewHistory }
			Mock Invoke-Migration {}
			Mock Set-Executed {}
			$arguments = @{
				ConnStr = 'Data Source=unused;Initial Catalog=unused'
				BasePath = $BasePath
				Phase = 'phase01'
				IgnoreScripts = @('IGNORED.SQL', 'unknown-ignore.sql')
				ForceScripts = @('NESTED\FORCE.SQL', 'FORCEDNEW.SQL', 'unknown-force.sql')
				Verbose = $true
				Confirm = $false
			}
			$preview = @(Invoke-Fast1Migration @arguments -WhatIf 4>&1 3>&1)
			Should -Invoke Get-Executed -Times 1 -Exactly
			Should -Invoke Invoke-Migration -Times 0 -Exactly
			Should -Invoke Set-Executed -Times 0 -Exactly
			$normal = @(Invoke-Fast1Migration @arguments 4>&1 3>&1)
			$previewDecisions = @($preview | Where-Object { "$_" -match '^(Run|Skip) migration script:' } | ForEach-Object { "$_" })
			$normalDecisions = @($normal | Where-Object { "$_" -match '^(Run|Skip) migration script:' } | ForEach-Object { "$_" })
			$normalDecisions | Should -Be $previewDecisions
			$previewDecisions | Should -Be @(
				'Run migration script: z[1].sql (New)'
				'Skip migration script: Nested/Old.sql (AlreadyExecuted)'
				'Skip migration script: ignored.sql (Ignored)'
				'Run migration script: Nested/Force.sql (Forced)'
				'Run migration script: ForcedNew.sql (Forced)'
			)
			$previewWarnings = @($preview | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { "$_" })
			$normalWarnings = @($normal | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { "$_" })
			$previewWarnings.Count | Should -Be 2
			$normalWarnings | Should -Be $previewWarnings
			Should -Invoke Get-Executed -Times 2 -Exactly
			Should -Invoke Invoke-Migration -Times 3 -Exactly
			Should -Invoke Set-Executed -Times 3 -Exactly
		}
	}

	It 'reports no work for <Kind> in both modes' -ForEach @(
		@{ Kind = 'empty' }
		@{ Kind = 'ignored' }
		@{ Kind = 'historical' }
	) {
		$names = @('one.sql')
		if ($Kind -eq 'empty') {
			$names = @()
		}
		$basePath = New-CommandFixture -Scripts $names
		InModuleScope 'Fast1data.SqlServer' -Parameters @{ BasePath = $basePath; Kind = $Kind } {
			$script:noWorkHistory = @()
			$selection = @{}
			if ($Kind -eq 'historical') {
				$script:noWorkHistory = @([PSCustomObject]@{ script_name = 'ONE.SQL'; checksum = (Get-FileChecksum (Join-Path $BasePath 'phase01/one.sql')) })
			}
			if ($Kind -eq 'ignored') {
				$selection.IgnoreScripts = @('one.sql')
			}
			Mock Get-Executed { $script:noWorkHistory }
			Mock Invoke-Migration {}
			Mock Set-Executed {}
			foreach ($preview in @($false, $true)) {
				$messages = @(Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath `
					-Phase 'phase01' @selection -WhatIf:$preview -Confirm:$false -Verbose 4>&1)
				@($messages | Where-Object { "$_" -eq 'Nothing to run' }).Count | Should -Be 1
			}
			Should -Invoke Get-Executed -Times 2 -Exactly
			Should -Invoke Invoke-Migration -Times 0 -Exactly
			Should -Invoke Set-Executed -Times 0 -Exactly
		}
	}

	It 'reports the identical validation error in execution and preview' {
		$basePath = New-CommandFixture
		InModuleScope 'Fast1data.SqlServer' -Parameters @{ BasePath = $basePath } {
			Mock Get-Executed { @([PSCustomObject]@{ script_name = 'LAST.SQL'; checksum = 'old' }) }
			Mock Invoke-Migration {}
			Mock Set-Executed {}
			$errors = @(
				foreach ($preview in @($false, $true)) {
					try {
						Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath `
							-Phase 'phase01' -WhatIf:$preview -Confirm:$false -ErrorAction Stop
						throw 'Expected checksum validation to fail.'
					}
					catch {
						$_.Exception.Message
					}
				}
			)
			$errors[0] | Should -BeLike '*Checksum mismatch*last.sql*Expected: old*Current:*'
			$errors[1] | Should -BeExactly $errors[0]
			Should -Invoke Invoke-Migration -Times 0 -Exactly
			Should -Invoke Set-Executed -Times 0 -Exactly
		}
	}
}

Describe 'Migration history coordination' {
	It 'executes then records each eligible script in configured order and preserves original update keys' {
		$basePath = New-CommandFixture -Scripts 'z.sql', 'Nested/Legacy.sql', 'a.sql', 'skip.sql'
		InModuleScope 'Fast1data.SqlServer' -Parameters @{ BasePath = $basePath } {
			$script:coordinationTrace = [System.Collections.Generic.List[string]]::new()
			$script:writtenRecords = [System.Collections.Generic.List[object]]::new()
			Mock Get-Executed { @([PSCustomObject]@{ script_name = 'NESTED\LEGACY.SQL'; checksum = 'old' }) }
			Mock Invoke-Migration {
				$script:coordinationTrace.Add("execute:$([System.IO.Path]::GetFileName($Script))")
			}
			Mock Set-Executed {
				$script:coordinationTrace.Add("write:$ScriptName")
				$script:writtenRecords.Add([PSCustomObject]@{
					Name = $ScriptName
					Original = $HistoryScriptName
					Update = $ForceScript
					Checksum = $Checksum
					Phase = $Phase
				})
			}
			Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath -Phase 'phase01' `
				-IgnoreScripts 'skip.sql' -ForceScripts 'nested/LEGACY.sql', 'A.SQL' -Confirm:$false
			$script:coordinationTrace.ToArray() | Should -Be @('execute:z.sql', 'write:z.sql', 'execute:Legacy.sql', 'write:Nested/Legacy.sql', 'execute:a.sql', 'write:a.sql')
			$script:writtenRecords.Name | Should -Be @('z.sql', 'Nested/Legacy.sql', 'a.sql')
			$script:writtenRecords.Update | Should -Be @($false, $true, $false)
			$script:writtenRecords[1].Original | Should -BeExactly 'NESTED\LEGACY.SQL'
			$script:writtenRecords[0].Original | Should -BeNullOrEmpty
			foreach ($record in $script:writtenRecords) {
				$record.Phase | Should -Be 'phase01'
				$record.Checksum | Should -Be (Get-FileChecksum (Join-Path $BasePath "phase01/$($record.Name)"))
			}
			Should -Invoke Get-Executed -Times 1 -Exactly
			Should -Invoke Set-Executed -Times 0 -Exactly -ParameterFilter { $ScriptName -eq 'skip.sql' }
		}
	}

	It 'stops on <Failure> failure, retains earlier progress, and retries truthfully' -ForEach @(
		@{ Failure = 'execution' }
		@{ Failure = 'recording' }
	) {
		$basePath = New-CommandFixture -Scripts 'first.sql', 'middle.sql', 'last.sql'
		InModuleScope 'Fast1data.SqlServer' -Parameters @{ BasePath = $basePath; Failure = $Failure } {
			$script:failureKind = $Failure
			$script:injectFailure = $true
			$script:failureTrace = [System.Collections.Generic.List[string]]::new()
			$script:durableHistory = [System.Collections.Generic.Dictionary[string, string]]::new()
			Mock Get-Executed {
				foreach ($entry in $script:durableHistory.GetEnumerator()) {
					[PSCustomObject]@{ script_name = $entry.Key; checksum = $entry.Value }
				}
			}
			Mock Invoke-Migration {
				$name = [System.IO.Path]::GetFileName($Script)
				$script:failureTrace.Add("execute:$name")
				if ($name -eq 'middle.sql' -and $script:injectFailure -and $script:failureKind -eq 'execution') {
					Write-Error 'injected execution failure'
				}
			}
			Mock Set-Executed {
				$script:failureTrace.Add("write:$ScriptName")
				if ($ScriptName -eq 'middle.sql' -and $script:injectFailure -and $script:failureKind -eq 'recording') {
					Write-Error 'injected recording failure'
				}
				$script:durableHistory[$ScriptName] = $Checksum
			}
			{
				Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath -Phase 'phase01' -Confirm:$false
			} | Should -Throw "*injected $Failure failure*"
			$script:durableHistory.Count | Should -Be 1
			$script:durableHistory.ContainsKey('first.sql') | Should -BeTrue
			$expected = @('execute:first.sql', 'write:first.sql', 'execute:middle.sql')
			if ($Failure -eq 'recording') {
				$expected += 'write:middle.sql'
			}
			$script:failureTrace.ToArray() | Should -Be $expected
			Should -Invoke Invoke-Migration -Times 0 -Exactly -ParameterFilter { $Script.EndsWith('last.sql') }
			Should -Invoke Set-Executed -Times 0 -Exactly -ParameterFilter { $ScriptName -eq 'last.sql' }
			$script:injectFailure = $false
			Invoke-Fast1Migration -ConnStr 'Data Source=unused;Initial Catalog=unused' -BasePath $BasePath -Phase 'phase01' -Confirm:$false
			$script:durableHistory.Count | Should -Be 3
			$script:failureTrace.ToArray() | Should -Be @($expected + @('execute:middle.sql', 'write:middle.sql', 'execute:last.sql', 'write:last.sql'))
			Should -Invoke Invoke-Migration -Times 1 -Exactly -ParameterFilter { $Script.EndsWith('first.sql') }
		}
	}
}
