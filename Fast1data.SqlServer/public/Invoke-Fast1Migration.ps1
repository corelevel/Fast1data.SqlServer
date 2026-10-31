<#
.SYNOPSIS
	Deploys migration scripts to the target SQL Server

.DESCRIPTION
	Reads history and validates the entire selected phase before confirmation or
	mutation. Literal phase selection preserves configured script order. Script
	identity matches case-insensitively with portable slash separators; actual file
	lookup retains configured casing under the host filesystem rules.

	Rejects duplicate names, global ignore/force conflicts, paths outside the phase,
	missing non-ignored files, and unforced checksum drift. Unknown selections warn.
	WhatIf performs the same history/file reads and reports ordered run/skip reasons
	with Verbose, while executing no migration scripts and writing no history. Empty/all-skipped
	phases report Nothing to run. Validation does not lock files or history.

	Each execution completes before its history write and before the next script.
	Either failure terminates; earlier completed work remains durable. SQL may
	succeed before history recording fails, so scripts must be idempotent for retry.
	Forced updates locate the original stored key and record a normalized relative
	name, SHA-256, and database UTC timestamp. No phase transaction is provided.
	Configuration and SQL files are executable administrator inputs. Set up the
	history schema and grant the required execution and history permissions first.

	Requires PowerShell 7.6+
	Requires SQL Server PowerShell module
	https://learn.microsoft.com/en-us/powershell/sql-server/download-sql-server-ps-module

.PARAMETER ConnStr
	SQL Server connection string

.PARAMETER BasePath
	Folder containing config file and migration scripts

.PARAMETER Phase
	Literal migration phase property and directory name; brackets are not wildcards.

.PARAMETER IgnoreScripts
	Optional list of scripts to skip during execution
	Case-insensitive phase-relative names; backslashes and forward slashes match.
	Contained rooted names are converted to phase-relative names. Ignored paths
	remain subject to containment but need not exist and are not hashed.
	Example: "001-fix-that.sql", "000-fix-this.sql"

.PARAMETER ForceScripts
	Optional list of migration script filenames to force execution even if
		they were previously recorded in the migration history table
	Case/separator matching follows IgnoreScripts. Force also permits new scripts;
	containment and existence still apply. Unknown names warn without adding work.
	Example: "job007/000-kill-all-user-processes.sql"

.INPUTS
	{
		"phase01": {
			"scripts": [
				"001-fix-that.sql",
				"000-fix-this.sql",
				"job007/000-kill-all-user-processes.sql"
			]
		},
		"phase02": {
			"scripts": [
				"000-do-cool-stuff.sql"
			]
		},
		"phase03": {
			"scripts": [
				"000-fix-this.sql"
			]
		}
	}
#>
function Invoke-Fast1Migration {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
		[string]$BasePath,

		[Parameter(Mandatory)]
		[string]$Phase,

		[string[]]$IgnoreScripts,

		[string[]]$ForceScripts
	)

	Set-StrictMode -Version Latest

	$history = @(Get-Executed -ConnStr $ConnStr -Phase $Phase -ErrorAction Stop)
	$evaluation = Resolve-MigrationPhase -BasePath $BasePath -Phase $Phase -History $history `
		-IgnoreScripts $IgnoreScripts -ForceScripts $ForceScripts -ErrorAction Stop
	foreach ($warning in $evaluation.Warnings) {
		Write-LogMessage -Message $warning -Level Warning
	}
	foreach ($script in $evaluation.Scripts) {
		Write-LogMessage -Message "$($script.Action) migration script: $($script.ScriptName) ($($script.Reason))" `
				-Level Verbose
	}
	$eligible = @($evaluation.Scripts | Where-Object Action -EQ 'Run')
	if ($eligible.Count -eq 0) {
		Write-LogMessage -Message 'Nothing to run' -Level Verbose
		return
	}
	$connStrParser = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnStr)
	$target = "DataSource: $($connStrParser.DataSource), InitialCatalog: $($connStrParser.InitialCatalog), Phase: $Phase"
	if ($PSCmdlet.ShouldProcess($target)) {
		foreach ($script in $eligible) {
			Invoke-Migration -ConnStr $ConnStr -Script $script.FullPath -ErrorAction Stop
			Set-Executed -ConnStr $ConnStr -ScriptName $script.ScriptName -Phase $Phase `
				-Checksum $script.Checksum -HistoryScriptName $script.HistoryScriptName `
				-ForceScript ($script.IsForced -and $script.WasExecuted) -ErrorAction Stop
			Write-LogMessage -Message "Migration completed: $($script.ScriptName)" -Level Verbose
		}
	}
}
