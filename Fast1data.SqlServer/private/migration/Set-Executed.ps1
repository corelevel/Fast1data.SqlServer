<#
.SYNOPSIS
Records a successfully executed migration script.

.DESCRIPTION
Inserts a migration-history record for a newly executed script. For a forced
rerun of an existing script, locates the original stored key and updates its name,
checksum and database UTC execution timestamp. Uses the borrowed command directly;
replaces its text/parameters but preserves timeout, connection and transaction.
The caller owns all resource cleanup, including after errors. A failed history
write can follow committed SQL and requires idempotent retry.

.PARAMETER SqlCmd
Caller-owned Microsoft.Data.SqlClient command with an already open connection.

.PARAMETER ScriptName
Specifies the portable, phase-relative script name stored in migration history.

.PARAMETER Phase
Specifies the migration phase associated with the script.

.PARAMETER Checksum
Specifies the SHA-256 checksum of the executed migration script.

.PARAMETER ForceScript
Indicates whether an existing migration-history record must be updated.

.PARAMETER HistoryScriptName
Original stored script name used to locate a forced historical update. Defaults
to ScriptName for existing private callers; inserts do not use this value.
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
		[AllowNull()]
		[Microsoft.Data.SqlClient.SqlCommand]$SqlCmd,

		[Parameter(Mandatory)]
		[string]$ScriptName,

		[Parameter(Mandatory)]
		[string]$Phase,

		[Parameter(Mandatory)]
		[string]$Checksum,

		[Parameter(Mandatory)]
		[bool]$ForceScript,

		[string]$HistoryScriptName = $ScriptName
	)

	if ($null -eq $SqlCmd -or $null -eq $SqlCmd.Connection -or
		$SqlCmd.Connection.State -ne [System.Data.ConnectionState]::Open) {
		throw 'SqlCmd must reference a command with an already open connection; the caller must open it.'
	}
	try {
		$query = ''
		if ($ForceScript) {
			$query = @'
set nocount on
update dbo.fast1_migration_history
set script_name = @script_name, [checksum] = @checksum, executed_at = sysutcdatetime()
where script_name = @history_script_name and phase = @phase

if @@rowcount = 0
begin
	raiserror('Forced execution failed. The script was not found in the migration history table',16,1)
end
'@
		}
		else {
			$query = @'
set nocount on
insert dbo.fast1_migration_history(script_name, phase, [checksum])
values(@script_name, @phase, @checksum)
'@
		}

		$SqlCmd.Parameters.Clear()
		$SqlCmd.CommandType = [System.Data.CommandType]::Text
		$SqlCmd.CommandText = $query
		$SqlCmd.Parameters.Add('@script_name', [System.Data.SqlDbType]::NVarChar, 255).Value = $ScriptName
		$SqlCmd.Parameters.Add('@history_script_name', [System.Data.SqlDbType]::NVarChar, 255).Value = $HistoryScriptName
		$SqlCmd.Parameters.Add('@phase', [System.Data.SqlDbType]::NVarChar, 32).Value = $Phase
		$SqlCmd.Parameters.Add('@checksum', [System.Data.SqlDbType]::Char, 64).Value = $Checksum
		$null = $SqlCmd.ExecuteNonQuery()
	}
	catch {
		throw [System.InvalidOperationException]::new(
			"Migration '$ScriptName' in phase '$Phase': history write failed.", $_.Exception
		)
	}
}
