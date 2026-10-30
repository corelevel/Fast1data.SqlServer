BeforeAll {
	$script:moduleRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $script:moduleRoot 'Fast1data.SqlServer.psd1'
	Import-Module $modulePath -Force

	$script:testConnectionString = @(
		'Data Source=(local)'
		'Initial Catalog=pester_migration'
		'User ID=pester'
		'Password=pester'
		'Encrypt=False'
		'TrustServerCertificate=True'
		'Application Name=Fast1data.SqlServer.Migration.Tests'
	) -join ';'

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

	function Invoke-TestSql {
		param(
			[Parameter(Mandatory)]
			[string]$Query,

			[hashtable]$Parameters = @{}
		)

		$connection = [Microsoft.Data.SqlClient.SqlConnection]::new(
			$script:testConnectionString
		)
		$command = $null

		try {
			$connection.Open()
			$command = $connection.CreateCommand()
			$command.CommandText = $Query

			foreach ($entry in $Parameters.GetEnumerator()) {
				$parameter = $command.Parameters.AddWithValue(
					"@$($entry.Key)",
					$entry.Value
				)
				$null = $parameter
			}

			$command.ExecuteScalar()
		}
		finally {
			if ($null -ne $command) {
				$command.Dispose()
			}
			$connection.Dispose()
		}
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
					$script:guardHistory = @([pscustomobject]@{ script_name = 'LAST.SQL'; checksum = 'expected' })
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
				[pscustomobject]@{ script_name = 'NESTED\OLD.SQL'; checksum = (Get-FileChecksum (Join-Path $BasePath 'phase01/Nested/Old.sql')) }
				[pscustomobject]@{ script_name = 'nested\force.SQL'; checksum = 'old' }
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
				$script:noWorkHistory = @([pscustomobject]@{ script_name = 'ONE.SQL'; checksum = (Get-FileChecksum (Join-Path $BasePath 'phase01/one.sql')) })
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
			Mock Get-Executed { @([pscustomobject]@{ script_name = 'LAST.SQL'; checksum = 'old' }) }
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
			Mock Get-Executed { @([pscustomobject]@{ script_name = 'NESTED\LEGACY.SQL'; checksum = 'old' }) }
			Mock Invoke-Migration {
				$script:coordinationTrace.Add("execute:$([System.IO.Path]::GetFileName($Script))")
			}
			Mock Set-Executed {
				$script:coordinationTrace.Add("write:$ScriptName")
				$script:writtenRecords.Add([pscustomobject]@{
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
					[pscustomobject]@{ script_name = $entry.Key; checksum = $entry.Value }
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

Describe 'Migration SQL integration' -Tag 'Integration' {
	BeforeAll {
		$schemaPath = Join-Path $script:moduleRoot 'schema\migration\tables.sql'
		Invoke-Sqlcmd `
			-ConnectionString $script:testConnectionString `
			-InputFile $schemaPath `
			-AbortOnError `
			-ErrorAction Stop |
			Out-Null

		function Set-SqlFixtureScript {
			[CmdletBinding(SupportsShouldProcess)]
			param ([System.Collections.Specialized.OrderedDictionary]$Scripts)
			if ($PSCmdlet.ShouldProcess($script:phasePath, 'Configure SQL test scripts')) {
				foreach ($entry in $Scripts.GetEnumerator()) {
					$path = Join-Path $script:phasePath $entry.Key
					$null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path))
					Set-Content -LiteralPath $path -Value $entry.Value -NoNewline
				}
				$config = @{}
				$config[$script:phase] = @{ scripts = @($Scripts.Keys) }
				$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:basePath 'migration.json')
			}
		}

		function Get-SqlFixtureHistory {
			$json = Invoke-TestSql -Query @'
select script_name, [checksum], executed_at from dbo.fast1_migration_history
where phase = @phase order by script_name for json path;
'@ -Parameters @{ phase = $script:phase }
			$json | ConvertFrom-Json
		}

		function Get-SqlFixtureInsert {
			param ([int]$Id)
			@"
if not exists (select 1 from dbo.$script:tableName where id = $Id)
	insert dbo.$script:tableName(id) values($Id);
"@
		}

		$script:databaseCollation = Invoke-TestSql -Query "select convert(nvarchar(128), databasepropertyex(db_name(), 'Collation'))"
		Write-Information "Integration database collation: $script:databaseCollation" -InformationAction Continue
	}

	BeforeEach {
		$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
		$script:phase = "p_$suffix"
		$script:tableName = "migration_test_$suffix"
		$script:basePath = Join-Path $TestDrive $script:phase
		$script:phasePath = Join-Path $script:basePath $script:phase
		$null = New-Item -Path $script:phasePath -ItemType Directory -Force

		@"
{
	"$script:phase": {
		"scripts": [
			"001-idempotent.sql"
		]
	}
}
"@ | Set-Content -LiteralPath (Join-Path $script:basePath 'migration.json')

		@"
if object_id(N'dbo.$script:tableName', N'U') is null
begin
	create table dbo.$script:tableName
	(
		id int not null constraint PK_$script:tableName primary key
	)
end

if not exists (select 1 from dbo.$script:tableName where id = 1)
begin
	insert dbo.$script:tableName(id) values(1)
end
"@ | Set-Content -LiteralPath (
			Join-Path $script:phasePath '001-idempotent.sql'
		)
	}

	AfterEach {
		Invoke-TestSql `
			-Query @"
delete dbo.fast1_migration_history where phase = @phase;
if object_id(N'dbo.$script:tableName', N'U') is not null
	drop table dbo.$script:tableName;
select 1;
"@ `
			-Parameters @{ phase = $script:phase } |
			Out-Null
	}

	It 'executes, records, skips, and safely forces an idempotent migration' {
		Invoke-Fast1Migration `
			-ConnStr $script:testConnectionString `
			-BasePath $script:basePath `
			-Phase $script:phase

		$rowCount = Invoke-TestSql `
			-Query "select count(*) from dbo.$script:tableName"
		$historyCount = Invoke-TestSql `
			-Query 'select count(*) from dbo.fast1_migration_history where phase = @phase' `
			-Parameters @{ phase = $script:phase }

		$rowCount | Should -Be 1
		$historyCount | Should -Be 1

		Invoke-Fast1Migration `
			-ConnStr $script:testConnectionString `
			-BasePath $script:basePath `
			-Phase $script:phase

		Invoke-Fast1Migration `
			-ConnStr $script:testConnectionString `
			-BasePath $script:basePath `
			-Phase $script:phase `
			-ForceScripts '001-IDEMPOTENT.SQL'

		$rowCount = Invoke-TestSql `
			-Query "select count(*) from dbo.$script:tableName"
		$historyCount = Invoke-TestSql `
			-Query 'select count(*) from dbo.fast1_migration_history where phase = @phase' `
			-Parameters @{ phase = $script:phase }

		$rowCount | Should -Be 1
		$historyCount | Should -Be 1
	}

	It 'previews real history including force without changing effects or any stored values' {
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$snapshotQuery = @"
select (select script_name, [checksum], executed_at from dbo.fast1_migration_history
where phase = @phase order by script_name for json path) + ':' +
convert(nvarchar(20), (select count(*) from dbo.$script:tableName));
"@
		$before = Invoke-TestSql -Query $snapshotQuery -Parameters @{ phase = $script:phase }
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
			-ForceScripts '001-IDEMPOTENT.SQL' -WhatIf -Verbose
		$after = Invoke-TestSql -Query $snapshotQuery -Parameters @{ phase = $script:phase }
		$after | Should -BeExactly $before
	}

	It 'executes ordered scripts, preserves skipped timestamps, and refreshes changed forced history without duplicates' {
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'z-first.sql' = $initial
			'nested/a-second.sql' = @"
if not exists (select 1 from dbo.$script:tableName where id = 1)
	throw 51000, 'execution order violated', 1;
if not exists (select 1 from dbo.fast1_migration_history where phase = N'$script:phase' and script_name = N'z-first.sql')
	throw 51000, 'recording order violated', 1;
$(Get-SqlFixtureInsert -Id 2)
"@
		})
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$before = @(Get-SqlFixtureHistory)
		$before.Count | Should -Be 2
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 2
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$skipped = @(Get-SqlFixtureHistory)
		($skipped | ConvertTo-Json -Compress) | Should -BeExactly ($before | ConvertTo-Json -Compress)
		# A deliberately old timestamp proves database time refreshed without relying on sleeps.
		Invoke-TestSql -Query "update dbo.fast1_migration_history set executed_at = '20000101' where phase = @phase; select 1" `
			-Parameters @{ phase = $script:phase } | Out-Null
		Add-Content -LiteralPath (Join-Path $script:phasePath 'nested/a-second.sql') -Value '-- changed forced rerun'
		$changed = Get-Content -LiteralPath (Join-Path $script:phasePath 'nested/a-second.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'z-first.sql' = $initial
			'nested/a-second.sql' = $changed
			'forced-new.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
			-ForceScripts 'NESTED\A-SECOND.SQL', 'FORCED-NEW.SQL' -Confirm:$false
		$after = @(Get-SqlFixtureHistory)
		$after.Count | Should -Be 3
		$second = $after | Where-Object script_name -EQ 'nested/a-second.sql'
		$second.script_name | Should -BeExactly 'nested/a-second.sql'
		$second.checksum | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:phasePath 'nested/a-second.sql')).Hash
		$second.checksum | Should -Not -Be ($before | Where-Object script_name -EQ 'nested/a-second.sql').checksum
		([datetime]$second.executed_at).Year | Should -BeGreaterThan 2000
		([datetime]($after | Where-Object script_name -EQ 'z-first.sql').executed_at).Year | Should -Be 2000
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 3
	}

	It 'updates legacy original keys (case-sensitive database required=<RequireCaseSensitive>)' -ForEach @(
		@{ RequireCaseSensitive = $false }
		@{ RequireCaseSensitive = $true }
	) {
		if ($RequireCaseSensitive -and $script:databaseCollation -notmatch '(_CS_|_BIN)') {
			Set-ItResult -Skipped -Because "Selected database collation $script:databaseCollation is not case-sensitive. Supply a case-sensitive disposable database."
			return
		}
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{ 'Nested/001-idempotent.sql' = $initial })
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		Invoke-TestSql -Query @'
update dbo.fast1_migration_history set script_name = @legacy, executed_at = '20000101'
where phase = @phase;
select 1;
'@ -Parameters @{ phase = $script:phase; legacy = 'NESTED\001-IDEMPOTENT.SQL' } | Out-Null
		$legacy = @(Get-SqlFixtureHistory)[0]
		$legacy.script_name | Should -BeExactly 'NESTED\001-IDEMPOTENT.SQL'
		Add-Content -LiteralPath (Join-Path $script:phasePath 'Nested/001-idempotent.sql') -Value '-- new checksum'
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
			-ForceScripts 'nested/001-IDEMPOTENT.SQL' -Confirm:$false
		$after = @(Get-SqlFixtureHistory)
		$after.Count | Should -Be 1
		$after[0].script_name | Should -BeExactly 'Nested/001-idempotent.sql'
		$after[0].checksum | Should -Not -Be $legacy.checksum
		$after[0].checksum | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:phasePath 'Nested/001-idempotent.sql')).Hash
		([datetime]$after[0].executed_at).Year | Should -BeGreaterThan 2000
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 1
	}

	It 'surfaces a later actual SQL execution error and retains only earlier recorded progress' {
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'first.sql' = $initial
			'fail.sql' = "throw 51000, 'fixture SQL execution failure', 1;"
			'last.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		} | Should -Throw
		$history = @(Get-SqlFixtureHistory)
		$history.Count | Should -Be 1
		$history[0].script_name | Should -BeExactly 'first.sql'
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 1") | Should -Be 1
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 3") | Should -Be 0
		# Repair only the fixture's failed SQL and retry: earlier success stays skipped.
		Set-Content -LiteralPath (Join-Path $script:phasePath 'fail.sql') -Value (Get-SqlFixtureInsert -Id 2)
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$retry = @(Get-SqlFixtureHistory)
		$retry.Count | Should -Be 3
		($retry | Where-Object script_name -EQ 'first.sql').executed_at | Should -Be $history[0].executed_at
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 3
	}

	It 'surfaces actual recording failure after SQL succeeds, stops later work, and retries idempotently' {
		$initial = Get-Content -LiteralPath (Join-Path $script:phasePath '001-idempotent.sql') -Raw
		Set-SqlFixtureScript -Scripts ([ordered]@{
			'first.sql' = $initial
			'middle.sql' = "$(Get-SqlFixtureInsert -Id 2)`ndelete dbo.fast1_migration_history where phase = N'$script:phase' and script_name = N'middle.sql';"
			'last.sql' = (Get-SqlFixtureInsert -Id 3)
		})
		Invoke-TestSql -Query @'
insert dbo.fast1_migration_history(phase, script_name, [checksum]) values(@phase, N'middle.sql', @checksum);
select 1;
'@ -Parameters @{ phase = $script:phase; checksum = ('0' * 64) } | Out-Null
		{
			Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase `
				-ForceScripts 'middle.sql' -Confirm:$false
		} | Should -Throw '*script was not found in the migration history table*'
		$history = @(Get-SqlFixtureHistory)
		$history.Count | Should -Be 1
		$history[0].script_name | Should -BeExactly 'first.sql'
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 2") | Should -Be 1
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName where id = 3") | Should -Be 0
		Invoke-Fast1Migration -ConnStr $script:testConnectionString -BasePath $script:basePath -Phase $script:phase -Confirm:$false
		$retry = @(Get-SqlFixtureHistory)
		$retry.Count | Should -Be 3
		($retry | Where-Object script_name -EQ 'first.sql').executed_at | Should -Be $history[0].executed_at
		(Invoke-TestSql -Query "select count(*) from dbo.$script:tableName") | Should -Be 3
	}
}
