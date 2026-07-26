<#
.SYNOPSIS
	Deploys migration scripts to the target SQL Server

.DESCRIPTION
	Deploys migration scripts to the target SQL Server in order
	Detects checksum drift and stops on mismatch

	Requires PowerShell 7.4+
	Requires SQL Server PowerShell module
	https://learn.microsoft.com/en-us/powershell/sql-server/download-sql-server-ps-module

.PARAMETER ConnStr
	SQL Server connection string

.PARAMETER BasePath
	Folder containing config file and migration scripts

.PARAMETER Phase
	Migration phase to execute

.PARAMETER IgnoreScripts
	Optional list of scripts to skip during execution
	Filenames must match entries defined in the configuration file
	Example: "001-fix-that.sql", "000-fix-this.sql"

.PARAMETER ForceScripts
	Optional list of migration script filenames to force execution even if
		they were previously recorded in the migration history table
	Filenames must match entries defined in the configuration file
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
		[ValidateScript({ Test-Path $_ -PathType Container })]
		[string]$BasePath,

		[Parameter(Mandatory)]
		[string]$Phase,

		[string[]]$IgnoreScripts,

		[string[]]$ForceScripts
	)

	Set-StrictMode -Version Latest

	try {
		$configFile = Join-Path $BasePath 'migration.json'
		$scriptsFolder = Join-Path $BasePath $Phase

		if (-not (Test-Path $configFile -PathType Leaf)) {
			throw "Migration configuration not found: $configFile"
		}

		if (-not (Test-Path $scriptsFolder -PathType Container)) {
			throw "Scripts folder not found: $scriptsFolder"
		}

		$scriptsRoot = [System.IO.Path]::GetFullPath($scriptsFolder)
		$separatorChars = [char[]]@(
			[System.IO.Path]::DirectorySeparatorChar
			[System.IO.Path]::AltDirectorySeparatorChar
		)
		$scriptsRootPrefix = $scriptsRoot.TrimEnd($separatorChars) +
			[System.IO.Path]::DirectorySeparatorChar
		$pathComparison = if ($IsWindows) {
			[System.StringComparison]::OrdinalIgnoreCase
		}
		else {
			[System.StringComparison]::Ordinal
		}

		$executedScriptList = @(Get-Executed -ConnStr $ConnStr -Phase $Phase)
		$scriptList = @(Get-Migration -ConfigFile $configFile -Phase $Phase)
		
		# Check for duplicates
		$duplicates = $scriptList | Group-Object | Where-Object Count -gt 1
		if ($duplicates) {
			$names = ($duplicates | Select-Object -ExpandProperty Name) -join ', '
			throw "Duplicate script names detected in configuration: $names"
		}

		if ($IgnoreScripts) {
			$IgnoreScripts = @($IgnoreScripts | ForEach-Object { $_.Replace('\', '/') })
		}

		if ($ForceScripts) {
			$ForceScripts = @($ForceScripts | ForEach-Object { $_.Replace('\', '/') })
		}

		# Check for intersection
		if ($IgnoreScripts -and $ForceScripts) {
			$names = $IgnoreScripts | Where-Object { $_ -in $ForceScripts }
			if ($names) {
				throw "Scripts cannot be both ignored and forced: $($names -join ', ')"
			}
		}

		$dryRun = $true
		$connStrParser = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new($ConnStr)
		$target = "DataSource: $($connStrParser.DataSource), InitialCatalog: " +
			"$($connStrParser.InitialCatalog), Phase: $Phase"

		if ($PSCmdlet.ShouldProcess($target)) {
			$dryRun = $false
		}
		else {
			Write-Verbose 'Dry run'
		}

		$executedScriptMap = [System.Collections.Generic.Dictionary[string, string]]::new(
			[System.StringComparer]::OrdinalIgnoreCase
		)
		foreach ($script in $executedScriptList) {
			$executedScriptMap[$script.script_name] = $script.checksum
		}

		if ($IgnoreScripts) {
			$notPresent = $IgnoreScripts | Where-Object { $_ -notin $scriptList }
			if ($notPresent) {
				Write-Warning "IgnoreScripts contains names not present in configuration: " +
					"$($notPresent -join ', ')"
			}
		}

		if ($ForceScripts) {
			$notPresent = $ForceScripts | Where-Object { $_ -notin $scriptList }
			if ($notPresent) {
				Write-Warning "ForceScripts contains names not present in configuration: " +
					"$($notPresent -join ', ')"
			}
		}

		$didGoodJob = $false
		foreach ($scriptName in $scriptList) {
			if ($IgnoreScripts) {
				if ($scriptName -in $IgnoreScripts) {
					Write-Verbose "Ignoring migration script: $scriptName"
					continue
				}
			}

			$forceScript = $false
			if ($ForceScripts) {
				if ($scriptName -in $ForceScripts) {
					Write-Verbose "Forcing migration script: $scriptName"
					$forceScript = $true
				}
			}

			$scriptFullPath = [System.IO.Path]::GetFullPath(
				(Join-Path $scriptsRoot $scriptName)
			)

			if (-not $scriptFullPath.StartsWith($scriptsRootPrefix, $pathComparison)) {
				throw "Migration script is outside the phase directory: $scriptName"
			}

			if (-not (Test-Path -LiteralPath $scriptFullPath -PathType Leaf)) {
				throw "Migration script not found: $scriptFullPath"
			}

			$scriptExecuted = $executedScriptMap.ContainsKey($scriptName)
			# Check for checksum difference
			$checksum = Get-FileChecksum -File $scriptFullPath
			if (-not $forceScript -and $scriptExecuted) {
				$executedChecksum = $executedScriptMap[$scriptName]
				if ($checksum -ne $executedChecksum) {
					throw "Checksum mismatch for migration script: $scriptName" +
						" Expected: $executedChecksum" +
						" Checksum: $checksum"
				}
				continue
			}

			$didGoodJob = $true
			Write-Verbose "Running migration script: $scriptName"
			if (-not $dryRun) {
				Invoke-Migration -ConnStr $ConnStr -Script $scriptFullPath

				$scriptName = Get-RelativePath `
					-RelativeTo $scriptsFolder `
					-Path $scriptFullPath

				$scriptName = $scriptName.Replace('\', '/')

				Set-Executed `
					-ConnStr $ConnStr `
					-ScriptName $scriptName `
					-Phase $Phase `
					-Checksum $checksum `
					-ForceScript ($forceScript -and $scriptExecuted)
				
				Write-Verbose 'Migration completed'
			}
			else {
				Write-Verbose 'Dry run migration completed'
			}
		}

		if (-not $didGoodJob) {
			Write-Verbose 'Nothing to run'
		}
	}
	catch {
		Write-Error "Failed to run migration: $_"
		throw
	}
}
