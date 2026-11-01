[CmdletBinding()]
param (
	[Parameter(Mandatory)][string]$DistributionRoot,
	[ValidateSet('Direct', 'Manifest', 'ModelFirst', 'Sentinel', 'Extension', 'Reuse', 'Fault')][string]$Scenario = 'Direct',
	[string]$FaultPath,
	[ValidateSet('Missing', 'Corrupt', 'RuntimeError')][string]$FaultKind = 'Missing',
	[ValidateSet('Root', 'Model')][string]$Consumer = 'Root',
	[switch]$Instrument
)

# Each invocation owns a fresh process. Only marked, disposable copies may be mutated.
$observation = [ordered]@{ Root = $DistributionRoot; Scenario = $Scenario; Consumer = $Consumer; Complete = $false; Errors = @() }
$loaderTrace = [System.Collections.Generic.List[object]]::new()
[AppDomain]::CurrentDomain.SetData('Fast1ModuleLoaderTrace', $loaderTrace)
$originalError = $null
try {
	if (-not [System.IO.Path]::IsPathFullyQualified($DistributionRoot)) {
		throw 'DistributionRoot must be absolute.'
	}
	$DistributionRoot = (Resolve-Path -LiteralPath $DistributionRoot -ErrorAction Stop).Path
	$observation.Root = $DistributionRoot
	if ($Instrument -or $Scenario -in @('Sentinel', 'Extension', 'Reuse', 'Fault')) {
		if (-not (Test-Path -LiteralPath (Join-Path $DistributionRoot '.loader-test-copy'))) {
			throw 'Mutation requires a marked disposable distribution copy.'
		}
	}
	if ($Instrument) {
		$rootPath = Join-Path $DistributionRoot 'Fast1data.SqlServer.psm1'
		$rootText = Get-Content -LiteralPath $rootPath -Raw
		$rootText = $rootText -replace '(?m)^(\s*)Import-SqlClientLib\s*$', "`$1Import-SqlClientLib`n[AppDomain]::CurrentDomain.GetData('Fast1ModuleLoaderTrace').Add(@{ Stage = 'bootstrap' })"
		Set-Content -LiteralPath $rootPath -Value $rootText
		foreach ($relative in @('private/shared/Load.ps1', 'private/audit/Get-ImportState.ps1', 'private/audit/Get-SqlAuditFile.ps1', 'private/audit/Get-SqlAuditFileEntry.ps1', 'private/audit/Import-SqlAuditFile.ps1', 'private/migration/Get-Executed.ps1', 'private/migration/Set-Executed.ps1', 'private/migration/Resolve-MigrationPhase.ps1', 'private/migration/Invoke-Migration.ps1', 'private/archiving/Load.ps1', 'private/archiving/Invoke-ArchivingProcess.ps1')) {
			$path = Join-Path $DistributionRoot $relative
			$code = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
			# Using declarations must remain before executable instrumentation.
			$lines = @($code -split '\r?\n')
			$declarations = @($lines | Where-Object { $_ -match '^using ' })
			$body = @($lines | Where-Object { $_ -notmatch '^using ' })
			$probe = '[AppDomain]::CurrentDomain.GetData(''Fast1ModuleLoaderTrace'').Add(@{ Stage = ''' + $relative + '''; Owner = $ExecutionContext.SessionState.Module.Name; SqlClient = ([AppDomain]::CurrentDomain.GetAssemblies().GetName().Name -contains ''Microsoft.Data.SqlClient'') })'
			Set-Content -LiteralPath $path -Value (@($declarations) + @($probe) + $body)
		}
	}
	if ($Scenario -eq 'Sentinel') {
		$nested = Join-Path $DistributionRoot 'private/shared/unlisted/nested'
		$null = New-Item -ItemType Directory -Path $nested -Force
		Set-Content -LiteralPath (Join-Path $nested 'Unexpected.ps1') -Value "throw 'Unlisted private file executed'"
	}
	if ($Scenario -eq 'Extension') {
		Set-Content -LiteralPath (Join-Path $DistributionRoot 'private/shared/LoaderExtension.ps1') -Value 'function Get-LoaderExtension { ''extension'' }'
		Add-Content -LiteralPath (Join-Path $DistributionRoot 'private/shared/Load.ps1') -Value '. "$PSScriptRoot/LoaderExtension.ps1"'
	}
	if ($Scenario -in @('ModelFirst', 'Reuse') -or $Consumer -eq 'Model') {
		. (Join-Path $DistributionRoot 'private/shared/Get-RuntimeIdentifier.ps1')
		. (Join-Path $DistributionRoot 'private/shared/Import-SqlClientLib.ps1')
		Import-SqlClientLib
		$loaderTrace.Add(@{ Stage = 'bootstrap' })
	}
	if ($Scenario -eq 'Reuse') {
		$assemblyBefore = [Microsoft.Data.SqlClient.SqlConnection].Assembly
		$runtimePath = Join-Path $DistributionRoot "lib/$(Get-RuntimeIdentifier)/Microsoft.Data.SqlClient.dll"
		# Rename a loaded Windows DLL rather than attempting to overwrite it.
		Rename-Item -LiteralPath $runtimePath -NewName 'Microsoft.Data.SqlClient.loaded.dll'
	}
	if ($Scenario -eq 'Fault') {
		if ($FaultPath -eq 'SqlClient') {
			. (Join-Path $DistributionRoot 'private/shared/Get-RuntimeIdentifier.ps1')
			$FaultPath = "lib/$(Get-RuntimeIdentifier)/Microsoft.Data.SqlClient.dll"
		}
		$target = [System.IO.Path]::GetFullPath((Join-Path $DistributionRoot $FaultPath))
		if (-not $target.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
			throw 'Fault path must stay inside the disposable distribution.'
		}
		switch ($FaultKind) {
			'Missing' {
				Remove-Item -LiteralPath $target -ErrorAction Stop
			}
			'Corrupt' {
				Set-Content -LiteralPath $target -Value 'not a valid dependency {'
			}
			'RuntimeError' {
				Set-Content -LiteralPath $target -Value "Write-Error 'controlled required dependency failure'"
			}
		}
	}
	# Import under nonterminating caller preferences: loaders must enforce required loads.
	$ErrorActionPreference = 'Continue'
	$VerbosePreference = 'SilentlyContinue'
	$WarningPreference = 'Continue'
	$before = @("$ErrorActionPreference", "$VerbosePreference", "$WarningPreference")
	$importErrors = @()
	$Error.Clear()
	$records = [System.Collections.Generic.List[object]]::new()
	try {
		if ($Scenario -eq 'ModelFirst' -or $Consumer -eq 'Model') {
			Import-Module (Join-Path $DistributionRoot 'private/archiving/ArchivingModel.psm1') -ErrorVariable +importErrors *>&1 | ForEach-Object { $records.Add($_) }
		}
		if ($Consumer -eq 'Root') {
			$entry = 'Fast1data.SqlServer.psm1'
			if ($Scenario -eq 'Manifest') {
				$entry = 'Fast1data.SqlServer.psd1'
			}
			Import-Module (Join-Path $DistributionRoot $entry) -ErrorVariable +importErrors *>&1 | ForEach-Object { $records.Add($_) }
		}
	}
	catch {
		$originalError = $_
	}
	# Declaration errors occur before loader runtime. PowerShell can report a rejected
	# Import-Module as a nonterminating caller error while never creating the module.
	$declarationErrors = @($Error | ForEach-Object { $_.ToString() })
	if ($null -eq $originalError -and $importErrors.Count -gt 0) {
		$originalError = $importErrors[0]
	}
	$after = @("$ErrorActionPreference", "$VerbosePreference", "$WarningPreference")
	$observation.PreferencesBefore = $before
	$observation.PreferencesAfter = $after
	if (($before -join ',') -ne ($after -join ',')) {
		throw 'Import changed caller preferences.'
	}
	$root = Get-Module Fast1data.SqlServer
	$model = Get-Module -All ArchivingModel | Select-Object -First 1
	$observation.ImportErrors = @($importErrors | ForEach-Object { $_.ToString() })
	$observation.DeclarationErrors = $declarationErrors
	$observation.OriginalError = "$originalError"
	$observation.Trace = @($loaderTrace)
	$observation.PublicCommands = @(Get-Command -Name Invoke-Fast1Audit, Invoke-Fast1Migration, Invoke-Fast1Archiving -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
	if ($Scenario -eq 'Fault') {
		if ($null -eq $originalError) {
			throw 'Required dependency did not terminate initialization.'
		}
		if ($observation.PublicCommands.Count -ne 0 -or ($Consumer -eq 'Model' -and $null -ne $model)) {
			throw 'Failed initialization left an affected operation/module usable.'
		}
		$details = "$originalError`n$($importErrors -join "`n")`n$($declarationErrors -join "`n")"
		$hasDependencyContext = $details -match [regex]::Escape([System.IO.Path]::GetFileName($FaultPath))
		# PowerShell's model compiler can replace an underlying Metadata import error
		# with the owning model path and unresolved metadata type names, before runtime.
		if ($FaultPath -eq 'private/archiving/Metadata.psm1') {
			$hasDependencyContext = $hasDependencyContext -or ($details -match 'ArchivingModel\.psm1' -and $details -match 'Unable to find type \[(TableColumn|IndexColumn)\]')
		}
		if (-not $hasDependencyContext) {
			throw "Dependency context missing: $details"
		}
		if ($FaultKind -eq 'RuntimeError' -and $details -notmatch 'controlled required dependency failure') {
			throw 'Original nonterminating dependency error was lost.'
		}
	}
	else {
		if ($null -ne $originalError -or $importErrors.Count -gt 0 -or $records.Count -gt 0) {
			throw "Unexpected initialization errors/output: $originalError $($records -join ' ')"
		}
		if ($null -eq $root -or $null -eq $model -or $observation.PublicCommands.Count -ne 3) {
			throw 'Import did not assemble both consumers and three public commands.'
		}
		$shared = @('Write-LogMessage', 'Get-GenericSqlCommand', 'Invoke-GenericSqlQuery', 'Close-GenericSqlResource', 'Add-GenericSqlCleanupFailure', 'Get-GenericSqlCleanupFailure', 'Get-FileChecksum', 'Get-RelativePath')
		$observation.Owners = @(
			foreach ($module in @($root, $model)) {
				foreach ($name in $shared) {
					$command = & $module { param ($Name) Get-Command $Name -ErrorAction Stop } $name
					if (-not [object]::ReferenceEquals($command.Module, $module) -or -not [object]::ReferenceEquals($command.Module.SessionState, $module.SessionState)) {
						throw "Wrong owner for $name in $($module.Name)."
					}
					if (-not $command.ScriptBlock.File.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar)) {
						throw "Wrong distribution for $name."
					}
					@{ Function = $name; Owner = $module.Name }
				}
				if ($Scenario -eq 'Extension' -and (& $module { Get-LoaderExtension }) -ne 'extension') {
					throw 'Shared-list extension did not reach both consumers.'
				}
			}
		)
		$ownerBefore = & $root { (Get-Command Write-LogMessage).Module }
		Import-Module (Join-Path $DistributionRoot 'private/archiving/ArchivingModel.psm1')
		if (-not [object]::ReferenceEquals($ownerBefore, (& $root { (Get-Command Write-LogMessage).Module }))) {
			throw 'Model import replaced root definitions.'
		}
		foreach ($module in Get-Module -All | Where-Object Name -In @('ArchivingModel', 'Metadata', 'GenericSqlParam')) {
			if ($module.ExportedCommands.Count -ne 0 -or -not $module.Path.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar)) {
				throw 'Type module exports/provenance changed.'
			}
		}
		$observation.Assembly = [Microsoft.Data.SqlClient.SqlConnection].Assembly.Location
		if ($Scenario -ne 'Manifest' -and -not $observation.Assembly.StartsWith($DistributionRoot + [System.IO.Path]::DirectorySeparatorChar)) {
			throw 'Cold/bootstrap import used another distribution assembly.'
		}
		if ($Scenario -eq 'Reuse' -and -not [object]::ReferenceEquals($assemblyBefore, [Microsoft.Data.SqlClient.SqlConnection].Assembly)) {
			throw 'Compatible assembly was not reused.'
		}
		if ($Instrument) {
			$sharedTrace = @($loaderTrace | Where-Object Stage -EQ 'private/shared/Load.ps1')
			if ($sharedTrace.Count -ne 2 -or @($sharedTrace.Owner | Sort-Object -Unique).Count -ne 2) {
				throw 'Expected exactly two shared executions in distinct consumers.'
			}
			$behaviorTrace = @($loaderTrace | Where-Object { $_.ContainsKey('SqlClient') })
			if ($loaderTrace[0].Stage -ne 'bootstrap' -or @($behaviorTrace | Where-Object SqlClient -NE $true).Count -gt 0) {
				throw 'Behavior ran before SqlClient bootstrap.'
			}
			$stages = @($loaderTrace.Stage)
			if ([array]::IndexOf($stages, 'private/archiving/Load.ps1') -ge [array]::IndexOf($stages, 'private/archiving/Invoke-ArchivingProcess.ps1')) {
				throw 'Adapter loaded before staged declarations.'
			}
		}
	}
	$observation.Complete = $true
}
catch {
	$observation.Errors = @($_.ToString(), $_.ScriptStackTrace)
}
'MODULE_LOADER_RESULT:' + ($observation | ConvertTo-Json -Depth 10 -Compress)
if (-not $observation.Complete) {
	exit 1
}
