<#
.SYNOPSIS
Loads the bundled Microsoft.Data.SqlClient assembly.

.DESCRIPTION
Determines the current runtime identifier and loads the matching bundled
Microsoft.Data.SqlClient assembly unless it is already loaded.
#>
function Import-SqlClientLib {
	[CmdletBinding()]
	param()

	if ([AppDomain]::CurrentDomain.GetAssemblies().GetName().Name -contains 'Microsoft.Data.SqlClient') {
		return
	}

	$rid = Get-RuntimeIdentifier
	$sqlClientDll = Join-Path $PSScriptRoot "..\..\lib\$rid\Microsoft.Data.SqlClient.dll"

	if (-not (Test-Path -LiteralPath $sqlClientDll)) {
		throw "Microsoft.Data.SqlClient was not found for runtime '$rid'. Expected: $sqlClientDll"
	}

	[System.Reflection.Assembly]::LoadFrom($sqlClientDll) | Out-Null
}
