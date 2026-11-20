using module ./private/shared/GenericSqlParam.psm1

Set-StrictMode -Version Latest

$previousErrorActionPreference = $ErrorActionPreference
$loadStage = 'runtime identifier bootstrap'
# Required loads must terminate even when the caller continues on errors.
$ErrorActionPreference = 'Stop'
try {
	. "$PSScriptRoot/private/shared/Get-RuntimeIdentifier.ps1"

	$loadStage = 'SqlClient bootstrap'
	. "$PSScriptRoot/private/shared/Import-RequiredLibrary.ps1"
	Import-RequiredLibrary -DllName Microsoft.Data.SqlClient.dll -RequiredTypeName Microsoft.Data.SqlClient.SqlConnection

	$loadStage = 'ScriptDom bootstrap'
	Import-RequiredLibrary -DllName Microsoft.SqlServer.TransactSql.ScriptDom.dll -RequiredTypeName Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser

	$loadStage = 'shared behavior'
	. "$PSScriptRoot/private/shared/Load.ps1"

	$loadStage = 'audit and migration behavior'
	. "$PSScriptRoot/private/audit/Get-ImportState.ps1"
	. "$PSScriptRoot/private/audit/Get-SqlAuditFile.ps1"
	. "$PSScriptRoot/private/audit/Get-SqlAuditFileEntry.ps1"
	. "$PSScriptRoot/private/audit/Import-SqlAuditFile.ps1"
	. "$PSScriptRoot/private/migration/Get-FileChecksum.ps1"
	. "$PSScriptRoot/private/migration/Get-RelativePath.ps1"
	. "$PSScriptRoot/private/migration/Get-Executed.ps1"
	. "$PSScriptRoot/private/migration/Set-Executed.ps1"
	. "$PSScriptRoot/private/migration/Resolve-MigrationPhase.ps1"
	. "$PSScriptRoot/private/migration/Invoke-Migration.ps1"

	$loadStage = 'archiving declarations and adapter'
	. "$PSScriptRoot/private/archiving/Load.ps1"
	. "$PSScriptRoot/private/archiving/Invoke-ArchivingProcess.ps1"

	$loadStage = 'public commands'
	$publicScripts = Get-ChildItem -LiteralPath "$PSScriptRoot/public" -Filter '*.ps1' -File
	foreach ($script in $publicScripts) {
		. $script.FullName
	}

	Export-ModuleMember -Function ($publicScripts.BaseName + @('Invoke-Fast1GenericSqlQuery', 'Invoke-Fast1GenericSqlQueryReader'))
}
catch {
	throw [System.InvalidOperationException]::new(
		"Root module initialization failed during $loadStage at '$($_.InvocationInfo.ScriptName)': $($_.Exception.Message)`n$($_.ScriptStackTrace)",
		$_.Exception
	)
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
}
