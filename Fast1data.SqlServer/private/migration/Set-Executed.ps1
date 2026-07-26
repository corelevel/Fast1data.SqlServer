using module ../shared/EasySqlParam.psm1

<#
.SYNOPSIS
Records a successfully executed migration script.

.DESCRIPTION
Inserts a migration-history record for a newly executed script. For a forced
rerun of an existing script, updates its checksum and execution timestamp.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the target
database.

.PARAMETER ScriptName
Specifies the portable, phase-relative script name stored in migration history.

.PARAMETER Phase
Specifies the migration phase associated with the script.

.PARAMETER Checksum
Specifies the SHA-256 checksum of the executed migration script.

.PARAMETER ForceScript
Indicates whether an existing migration-history record must be updated.
#>
function Set-Executed {
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
		'PSUseShouldProcessForStateChangingFunctions',
		'',
		Justification = 'Private helper called only after Invoke-Fast1Migration performs ShouldProcess validation.'
	)]
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$ScriptName,

		[Parameter(Mandatory)]
		[string]$Phase,

		[Parameter(Mandatory)]
		[string]$Checksum,

		[Parameter(Mandatory)]
		[bool]$ForceScript
	)

	$sqlConn = $null
	try {
		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr

		$query = ''
		if ($ForceScript) {
			$query = @'
update dbo.fast1_migration_history
set [checksum] = @checksum, executed_at = sysutcdatetime()
where script_name = @script_name and phase = @phase

if @@rowcount = 0
begin
	raiserror('Forced execution failed. The script was not found in the migration history table',16,1)
end
'@
		}
		else {
			$query = @'
insert dbo.fast1_migration_history(script_name, phase, [checksum])
values(@script_name, @phase, @checksum)
'@
		}

		$sqlConn.Open()
		Invoke-EasySqlQuery `
			-SqlConn $sqlConn `
			-Query $query `
			-Parameters @{
				script_name = [EasySqlParam]@{
					Value = $ScriptName
					Type = [System.Data.SqlDbType]::NVarChar
					Size = 255
				}
				phase = [EasySqlParam]@{
					Value = $Phase
					Type = [System.Data.SqlDbType]::NVarChar
					Size = 32
				}
				checksum = [EasySqlParam]@{
					Value = $Checksum
					Type = [System.Data.SqlDbType]::Char
					Size = 64
				}
			}
	}
	finally {
		if ($null -ne $sqlConn) {
			$sqlConn.Dispose()
		}
	}
}
