using module ../shared/GenericSqlParam.psm1
. "$PSScriptRoot\..\shared\GenericSqlQuery.ps1"

<#
.SYNOPSIS
Records a successfully executed migration script.

.DESCRIPTION
Inserts a migration-history record for a newly executed script. For a forced
rerun of an existing script, locates the original stored key and updates its name,
checksum and database UTC execution timestamp.

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
		[string]$ConnStr,

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

	$sqlConn = $null
	$operationError = $null
	try {
		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr

		$query = ''
		if ($ForceScript) {
			$query = @'
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
insert dbo.fast1_migration_history(script_name, phase, [checksum])
values(@script_name, @phase, @checksum)
'@
		}

		$sqlConn.Open()
		Invoke-GenericSqlQuery `
			-SqlConn $sqlConn `
			-Query $query `
			-Parameters @{
				script_name = [GenericSqlParam]@{
					Value = $ScriptName
					Type = [System.Data.SqlDbType]::NVarChar
					Size = 255
				}
				phase = [GenericSqlParam]@{
					Value = $Phase
					Type = [System.Data.SqlDbType]::NVarChar
					Size = 32
				}
				checksum = [GenericSqlParam]@{
					Value = $Checksum
					Type = [System.Data.SqlDbType]::Char
					Size = 64
				}
				history_script_name = [GenericSqlParam]@{
					Value = $HistoryScriptName
					Type = [System.Data.SqlDbType]::NVarChar
					Size = 255
				}
			}
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
