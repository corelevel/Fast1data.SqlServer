[CmdletBinding()]
param (
	[Parameter(Mandatory)][string]$DistributionRoot,
	[Parameter(Mandatory)][string]$FixtureRoot,
	[Parameter(Mandatory)][ValidateSet('Windows', 'Linux', 'macOS', 'Unknown')][string]$OperatingSystem,
	[Parameter(Mandatory)][string]$OSArchitecture,
	[Parameter(Mandatory)][string]$ProcessArchitecture,
	[ValidateSet('Selector', 'psd1', 'psm1')][string]$EntryPoint = 'Selector',
	[switch]$StaleBundle,
	[switch]$Preload
)

$ErrorActionPreference = 'Stop'
$observation = [ordered]@{
	OperatingSystem = $OperatingSystem; OSArchitecture = $OSArchitecture; ProcessArchitecture = $ProcessArchitecture
	EntryPoint = $EntryPoint; StaleBundle = [bool]$StaleBundle; Preload = [bool]$Preload
	Complete = $false; Error = $null; HarnessError = $null; Rid = $null; PreloadedTypes = @(); Probes = @()
}
try {
	if (-not [System.IO.Path]::IsPathFullyQualified($FixtureRoot)) {
		throw 'FixtureRoot must be absolute.'
	}
	$FixtureRoot = [System.IO.Path]::GetFullPath($FixtureRoot)
	$parent = [System.IO.Directory]::GetParent($FixtureRoot).FullName
	if (-not (Test-Path -LiteralPath (Join-Path $parent '.runtime-test-parent') -PathType Leaf) -or
		[System.IO.Path]::GetFileName($FixtureRoot) -notmatch '^[a-f0-9]{32}$' -or
		(Test-Path -LiteralPath $FixtureRoot)) {
		throw 'Mutation requires a new GUID directory under a marked disposable parent.'
	}
	$DistributionRoot = (Resolve-Path -LiteralPath $DistributionRoot).Path
	# Parsing the enum before interpolation prevents arbitrary code in substituted facts.
	$osArch = [System.Runtime.InteropServices.Architecture]([Enum]::Parse([System.Runtime.InteropServices.Architecture], $OSArchitecture))
	$processArch = [System.Runtime.InteropServices.Architecture]([Enum]::Parse([System.Runtime.InteropServices.Architecture], $ProcessArchitecture))
	$null = New-Item -Path $FixtureRoot -ItemType Directory
	Set-Content -LiteralPath (Join-Path $FixtureRoot '.runtime-test-copy') -Value $FixtureRoot
	foreach ($name in @('Fast1data.SqlServer.psd1', 'Fast1data.SqlServer.psm1', 'private', 'public')) {
		Copy-Item -LiteralPath (Join-Path $DistributionRoot $name) -Destination $FixtureRoot -Recurse
	}
	function Invoke-FixtureSubstitution {
		param ([string]$Path, [string]$Needle, [string]$Replacement, [int]$Expected = 1)
		if (-not (Test-Path -LiteralPath (Join-Path $FixtureRoot '.runtime-test-copy'))) {
			throw 'Disposable marker missing.'
		}
		$absolute = [System.IO.Path]::GetFullPath($Path)
		if (-not $absolute.StartsWith($FixtureRoot + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal)) {
			throw 'Substitution path escaped the disposable copy.'
		}
		$code = Get-Content -LiteralPath $absolute -Raw
		$count = [regex]::Matches($code, [regex]::Escape($Needle)).Count
		if ($count -ne $Expected) {
			throw "Expected $Expected substitution(s), found $count for $Needle"
		}
		Set-Content -LiteralPath $absolute -Value $code.Replace($Needle, $Replacement)
	}
	$resolver = Join-Path $FixtureRoot 'private/shared/Get-RuntimeIdentifier.ps1'
	foreach ($os in @('Windows', 'Linux', 'macOS')) {
		$count = [regex]::Matches((Get-Content -LiteralPath $resolver -Raw), [regex]::Escape('$Is' + $os)).Count
		# macOS may be rejected by the default OS branch without a dedicated flag read.
		if ($os -eq 'macOS' -and $count -eq 0) {
			continue
		}
		$literal = '$false'
		if ($OperatingSystem -eq $os) {
			$literal = '$true'
		}
		Invoke-FixtureSubstitution -Path $resolver -Needle ('$Is' + $os) -Replacement $literal
	}
	Invoke-FixtureSubstitution -Path $resolver -Needle '[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture' -Replacement "[System.Runtime.InteropServices.Architecture]::$osArch"
	$processExpression = '[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture'
	$processReads = [regex]::Matches((Get-Content -LiteralPath $resolver -Raw), [regex]::Escape($processExpression)).Count
	# The pre-change resolver has no process read; matrix regressions expose that gap.
	if ($processReads -gt 0) {
		Invoke-FixtureSubstitution -Path $resolver -Needle $processExpression -Replacement "[System.Runtime.InteropServices.Architecture]::$processArch"
	}
	$observation.ProcessReads = $processReads
	if ($StaleBundle -or $Preload) {
		$hostRid = 'linux-x64'
		if ($IsWindows) {
			$hostRid = 'win-x64'
		}
		$assets = Join-Path $DistributionRoot "lib/$hostRid"
		$copyPaths = @()
		if ($StaleBundle) {
			$copyPaths += Join-Path $FixtureRoot 'lib/osx-x64'
		}
		if ($Preload) {
			$copyPaths += Join-Path $FixtureRoot 'preload'
		}
		foreach ($copyPath in $copyPaths) {
			$null = New-Item -Path $copyPath -ItemType Directory -Force
			foreach ($dll in @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll', 'Microsoft.SqlServer.Server.dll')) {
				Copy-Item -LiteralPath (Join-Path $assets $dll) -Destination $copyPath
				$null = [System.Reflection.AssemblyName]::GetAssemblyName((Join-Path $copyPath $dll))
			}
		}
		if ($Preload) {
			$types = @()
			foreach ($library in @(
				@{ Dll = 'Microsoft.Data.SqlClient.dll'; Type = 'Microsoft.Data.SqlClient.SqlConnection' }
				@{ Dll = 'Microsoft.SqlServer.TransactSql.ScriptDom.dll'; Type = 'Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser' }
			)) {
				$assembly = [System.Reflection.Assembly]::LoadFrom((Join-Path $FixtureRoot "preload/$($library.Dll)"))
				$types += $assembly.GetType($library.Type, $true, $false).FullName
			}
			$observation.PreloadedTypes = $types
		}
	}
	$trace = [System.Collections.Generic.List[string]]::new()
	[AppDomain]::CurrentDomain.SetData('Fast1RuntimeSupportTrace', $trace)
	$loader = Join-Path $FixtureRoot 'private/shared/Import-RequiredLibrary.ps1'
	foreach ($probe in @(
		@{ Needle = '$bundlePath = '; Stage = 'BundleLookup' }
		@{ Needle = 'foreach ($loaded in [AppDomain]::CurrentDomain.GetAssemblies()) {'; Stage = 'AssemblyReuse' }
		@{ Needle = '$assembly = [System.Reflection.Assembly]::LoadFrom($expectedPath)'; Stage = 'AssemblyLoad' }
	)) {
		$prefix = "[AppDomain]::CurrentDomain.GetData('Fast1RuntimeSupportTrace').Add('$($probe.Stage)')`n`t"
		Invoke-FixtureSubstitution -Path $loader -Needle $probe.Needle -Replacement ($prefix + $probe.Needle)
	}
	$rootModule = Join-Path $FixtureRoot 'Fast1data.SqlServer.psm1'
	$needle = '$loadStage = ''shared behavior'''
	Invoke-FixtureSubstitution -Path $rootModule -Needle $needle -Replacement ("[AppDomain]::CurrentDomain.GetData('Fast1RuntimeSupportTrace').Add('OperationalLoad')`n`t" + $needle)
	# Breakpoints observe database creation/execution lines in unchanged operation files.
	# Preloading is complete before probes are enabled. Nothing is executed by these probes.
	foreach ($file in Get-ChildItem -LiteralPath $FixtureRoot -Recurse -File | Where-Object Extension -In @('.ps1', '.psm1')) {
		$lineNumber = 0
		foreach ($line in Get-Content -LiteralPath $file.FullName) {
			$lineNumber++
			if ($line -match 'SqlConnection\]::new|\.Open\(|\.Execute(Reader|Scalar|NonQuery)\(') {
				$null = Set-PSBreakpoint -Script $file.FullName -Line $lineNumber -Action {
					[AppDomain]::CurrentDomain.GetData('Fast1RuntimeSupportTrace').Add('DatabaseAttempt')
				}
			}
		}
	}
	try {
		if ($EntryPoint -eq 'Selector') {
			. $resolver
			$observation.Rid = Get-RuntimeIdentifier
		}
		else {
			Import-Module (Join-Path $FixtureRoot "Fast1data.SqlServer.$EntryPoint") -ErrorAction Stop
		}
	}
	catch {
		$observation.Error = $_.Exception.Message
	}
	$observation.Probes = @($trace.ToArray())
	$observation.Complete = $true
}
catch {
	$observation.HarnessError = $_.Exception.Message
}
'RUNTIME_SUPPORT_RESULT:' + ($observation | ConvertTo-Json -Depth 8 -Compress)
if (-not $observation.Complete) {
	exit 1
}
