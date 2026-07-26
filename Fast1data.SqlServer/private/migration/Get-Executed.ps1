<#
.SYNOPSIS
Gets migration scripts already recorded as executed.

.DESCRIPTION
Reads script names and checksums from dbo.fast1_migration_history for the
specified phase. Script paths are returned with portable forward-slash
separators.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the target
database.

.PARAMETER Phase
Specifies the migration phase whose execution history is returned.
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
	$sqlCmd = $null
	$sqlReader = $null

	try {
		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr
		$query = @'
select script_name, [checksum]
from dbo.fast1_migration_history
where phase = @phase
'@

		$sqlConn.Open()
		$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($query, $sqlConn)
		$sqlCmd.CommandType = [System.Data.CommandType]::Text
		$pPhase = $sqlCmd.Parameters.Add('@phase', [System.Data.SqlDbType]::NVarChar, 32)
		$pPhase.Value = $Phase
		$sqlReader = $sqlCmd.ExecuteReader()

		while ($sqlReader.Read()) {
			[PSCustomObject]@{
				script_name = $sqlReader['script_name'].Replace('\', '/')
				checksum = $sqlReader['checksum']
			}
		}
	}
	finally {
		if ($null -ne $sqlReader) {
			$sqlReader.Dispose()
		}
		if ($null -ne $sqlCmd) {
			$sqlCmd.Dispose()
		}
		if ($null -ne $sqlConn) {
			$sqlConn.Dispose()
		}
	}
}
