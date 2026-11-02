# Reuse an existing selected-root session so matrix assertions retain its import history.
param ([Parameter(Mandatory)][string]$DistributionRoot)

$selectedRoot = (Resolve-Path -LiteralPath $DistributionRoot).Path
$loaded = Get-Module Fast1data.SqlServer
if ($loaded -and $loaded.ModuleBase -ne $selectedRoot) {
	throw 'A different distribution is already loaded; use a fresh PowerShell process.'
}
if (-not $loaded) {
	$loaded = Import-Module (Join-Path $selectedRoot 'Fast1data.SqlServer.psd1') -PassThru
}
& $loaded {
	param ($Root)
	foreach ($path in @('private/archiving/ArchivingModel.psm1', 'private/archiving/Metadata.psm1', 'private/shared/GenericSqlParam.psm1')) {
		Import-Module (Join-Path $Root $path) -ErrorAction Stop
	}
} $selectedRoot
