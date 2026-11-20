<#
.SYNOPSIS
Gets migration scripts already recorded as executed.

.DESCRIPTION
Reads script names and checksums from dbo.fast1_migration_history for the
specified phase. Stored script names are returned exactly as persisted so forced
updates can locate the original key; phase evaluation owns identity normalization.
Streams Invoke-Fast1GenericSqlQueryReader directly with a typed NVarChar(32) phase filter.
The row command releases reader then command before this function releases its
owned connection, including failure and downstream truncation. A later failure
can leave previously delivered rows; cleanup preserves primary operation errors.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the target
database.

.PARAMETER Phase
Specifies the migration phase whose execution history is returned.

.INPUTS
None. This private function does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject. Zero or more rows with script_name
then checksum, retaining exact persisted spelling, case, separators and checksums.

.EXAMPLE
Get-Executed -ConnStr $testConnectionString -Phase phase01

Reads history on a connection owned by this private helper. Execution ordering,
checksums, force/ignore, preview and idempotent retry behavior remain unchanged.
#>
function Get-Executed {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$Phase
	)

	$sqlConn = $null

	$operationError = $null
	try {
		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr
		$query = @'
set nocount on
select script_name, [checksum]
from dbo.fast1_migration_history
where phase = @phase
'@

		$sqlConn.Open()
		# Read-only history discovery still needs its descriptor during migration preview.
		$parameters = @{ phase = New-Fast1GenericSqlParam -Type NVarChar -Size 32 -Value $Phase -WhatIf:$false -Confirm:$false }
		Invoke-Fast1GenericSqlQueryReader -SqlConn $sqlConn -Query $query -CommandType Text -Parameters $parameters
	}
	catch {
		$operationError = $_
		throw
	}
	finally {
		Close-GenericSqlResource -Resources ([ordered]@{ Connection = $sqlConn }) `
			-PrimaryError $operationError
	}
}
