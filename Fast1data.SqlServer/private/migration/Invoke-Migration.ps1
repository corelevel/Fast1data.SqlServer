<#
.SYNOPSIS
Executes one SQL Server migration script.

.DESCRIPTION
Runs a migration script through Invoke-Sqlcmd and converts SQL execution errors
into terminating errors so the caller does not record a failed migration.

.PARAMETER ConnStr
Specifies the SQL Server connection string used to execute the script.

.PARAMETER Script
Specifies the path to the SQL migration script to execute.
#>
function Invoke-Migration {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$Script
	)

	try {
		Invoke-Sqlcmd -ConnectionString $ConnStr -InputFile $Script `
			-AbortOnError -ErrorAction Stop |
			Out-Null
	}
	catch {
		Write-Error "Failed to run migration script: $Script"
		throw
	}
}
