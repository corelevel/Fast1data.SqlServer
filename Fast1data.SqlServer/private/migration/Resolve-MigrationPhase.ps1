<#
.SYNOPSIS
Evaluates a complete migration phase without executing SQL or writing history.

.DESCRIPTION
Reads literal configuration and files and returns one ordered decision snapshot.
Script identity uses ordinal case-insensitive matching and portable separators.
Filesystem lookup retains configured spelling. The snapshot does not lock inputs.

.PARAMETER BasePath
Existing directory containing migration.json and the selected phase directory.

.PARAMETER Phase
Literal phase property and directory name.

.PARAMETER History
Previously recorded script_name/checksum entries for this phase only.

.PARAMETER IgnoreScripts
Names to skip, subject to containment but not file existence or checksum checks.

.PARAMETER ForceScripts
Names to run despite history or checksum drift; files must exist and be contained.
#>
function Resolve-MigrationPhase {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$BasePath,

		[Parameter(Mandatory)]
		[string]$Phase,

		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[object[]]$History,

		[AllowEmptyCollection()]
		[string[]]$IgnoreScripts = @(),

		[AllowEmptyCollection()]
		[string[]]$ForceScripts = @()
	)

	Set-StrictMode -Version Latest
	$baseDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BasePath)
	$configFile = [System.IO.Path]::GetFullPath((Join-Path $baseDirectory 'migration.json'))
	if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
		throw "Migration configuration not found: $configFile"
	}
	$config = Get-Content -LiteralPath $configFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
	$phaseProperty = $config.PSObject.Properties[$Phase]
	if ($null -eq $phaseProperty) {
		throw "Migration phase not found: $Phase"
	}
	$phaseDirectory = [System.IO.Path]::GetFullPath((Join-Path $baseDirectory $Phase))
	if (-not (Test-Path -LiteralPath $phaseDirectory -PathType Container)) {
		throw "Migration phase directory not found: $phaseDirectory"
	}
	$pathComparison = [System.StringComparison]::Ordinal
	if ($IsWindows) {
		$pathComparison = [System.StringComparison]::OrdinalIgnoreCase
	}
	$separator = [System.IO.Path]::DirectorySeparatorChar
	$phasePrefix = $phaseDirectory.TrimEnd([char[]]@('/', '\')) + $separator

	# Identity is deliberately narrower than filesystem canonicalization: relative
	# dot segments retain their spelling; only contained rooted names are relativized.
	function ConvertTo-PhaseScriptName {
		param ([string]$Name)
		$normalized = $Name.Replace('\', '/')
		if ([System.IO.Path]::IsPathRooted($normalized)) {
			$fullPath = [System.IO.Path]::GetFullPath($normalized, $phaseDirectory)
			if ($fullPath.StartsWith($phasePrefix, $pathComparison)) {
				return (Get-RelativePath -RelativeTo $phaseDirectory -Path $fullPath).Replace('\', '/')
			}
		}
		return $normalized
	}

	$configuredNames = [System.Collections.Generic.List[string]]::new()
	$configuredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($name in $phaseProperty.Value.scripts) {
		$identity = ConvertTo-PhaseScriptName -Name $name
		if (-not $configuredSet.Add($identity)) {
			throw "Duplicate script names detected in phase '${Phase}': $identity"
		}
		$configuredNames.Add($identity)
	}
	$ignoreSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$forceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$ignoreNames = @(
		foreach ($name in $IgnoreScripts) {
			ConvertTo-PhaseScriptName -Name $name
		}
	)
	$forceNames = @(
		foreach ($name in $ForceScripts) {
			ConvertTo-PhaseScriptName -Name $name
		}
	)
	foreach ($name in $ignoreNames) {
		$null = $ignoreSet.Add($name)
	}
	foreach ($name in $forceNames) {
		if ($ignoreSet.Contains($name)) {
			throw "Scripts cannot be both ignored and forced in phase '${Phase}': $name"
		}
		$null = $forceSet.Add($name)
	}
	$warnings = [System.Collections.Generic.List[string]]::new()
	foreach ($name in $ignoreNames) {
		if (-not $configuredSet.Contains($name)) {
			$warnings.Add("IgnoreScripts name not present in phase '${Phase}' configuration: $name")
		}
	}
	foreach ($name in $forceNames) {
		if (-not $configuredSet.Contains($name)) {
			$warnings.Add("ForceScripts name not present in phase '${Phase}' configuration: $name")
		}
	}
	$historyMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($entry in $History) {
		$historyMap[(ConvertTo-PhaseScriptName -Name $entry.script_name)] = $entry
	}
	$scripts = [System.Collections.Generic.List[object]]::new()
	foreach ($name in $configuredNames) {
		$fullPath = [System.IO.Path]::GetFullPath($name, $phaseDirectory)
		if (-not $fullPath.StartsWith($phasePrefix, $pathComparison)) {
			throw "Migration script is outside the phase directory '${Phase}': $name ($fullPath)"
		}
		$wasExecuted = $historyMap.ContainsKey($name)
		$historyScriptName = $null
		if ($wasExecuted) {
			$historyScriptName = $historyMap[$name].script_name
		}
		$isForced = $forceSet.Contains($name)
		$checksum = $null
		$action = 'Skip'
		$reason = 'Ignored'
		if (-not $ignoreSet.Contains($name)) {
			if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
				throw "Migration script not found in phase '${Phase}': $name ($fullPath)"
			}
			$checksum = Get-FileChecksum -File $fullPath
			if ($isForced) {
				$action = 'Run'
				$reason = 'Forced'
			}
			elseif ($wasExecuted) {
				if ($checksum -ne $historyMap[$name].checksum) {
					throw "Checksum mismatch in phase '${Phase}' for migration script: $name Expected: $($historyMap[$name].checksum) Current: $checksum"
				}
				$reason = 'AlreadyExecuted'
			}
			else {
				$action = 'Run'
				$reason = 'New'
			}
		}
		$scripts.Add([pscustomobject]@{
			ScriptName = $name
			FullPath = $fullPath
			Checksum = $checksum
			WasExecuted = $wasExecuted
			HistoryScriptName = $historyScriptName
			IsForced = $isForced
			Action = $action
			Reason = $reason
		})
	}

	[pscustomobject]@{
		Phase = $Phase
		ConfigFile = $configFile
		PhaseDirectory = $phaseDirectory
		Scripts = $scripts.ToArray()
		Warnings = $warnings.ToArray()
	}
}
