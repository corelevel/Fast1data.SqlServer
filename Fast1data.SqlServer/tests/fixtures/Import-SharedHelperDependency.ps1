# Reuse an existing selected-root session so matrix assertions retain its import history.
param ([Parameter(Mandatory)][string]$DistributionRoot)

$selectedRoot = (Resolve-Path -LiteralPath $DistributionRoot).Path
. (Join-Path $selectedRoot 'private/shared/Get-RuntimeIdentifier.ps1')
foreach ($assembly in @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')) {
	$asset = Join-Path $selectedRoot "lib/$(Get-RuntimeIdentifier)/$assembly"
	if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
		throw "Selected distribution dependency missing: $asset. Rebuild dependencies."
	}
}
$loaded = Get-Module Fast1data.SqlServer
if ($loaded -and $loaded.ModuleBase -ne $selectedRoot) {
	throw 'A different distribution is already loaded; use a fresh PowerShell process.'
}
if (-not $loaded) {
	$loaded = Import-Module (Join-Path $selectedRoot 'Fast1data.SqlServer.psd1') -PassThru
}
& $loaded {
	Import-RequiredLibrary -DllName Microsoft.Data.SqlClient.dll -RequiredTypeName Microsoft.Data.SqlClient.SqlConnection
	Import-RequiredLibrary -DllName Microsoft.SqlServer.TransactSql.ScriptDom.dll -RequiredTypeName Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser
}
& $loaded {
	param ($Root)
	foreach ($path in @('private/archiving/ArchivingModel.psm1', 'private/archiving/Metadata.psm1', 'private/shared/GenericSqlParam.psm1')) {
		Import-Module (Join-Path $Root $path) -ErrorAction Stop
	}
} $selectedRoot
