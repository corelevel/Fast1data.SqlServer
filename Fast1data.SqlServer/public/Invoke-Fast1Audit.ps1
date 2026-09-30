<#
.SYNOPSIS
Imports SQL Server Audit files into the Fast1 Audit database.

.DESCRIPTION
Discovers SQL Server Audit files in a folder, retrieves the saved import state
for each unique audit GUID, imports new records, and reports processed and
imported record counts through the verbose stream.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the Fast1 Audit
database.

.PARAMETER Folder
Specifies the folder containing the SQL Server Audit files to process.

.PARAMETER LogFile
Specifies an optional file to which Fast1 Audit log messages are appended.
#>
function Invoke-Fast1Audit {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[ValidateScript({ Test-Path $_ -PathType Container })]
		[string]$Folder,

		[string]$LogFile
	)

	[int]$rowProcessed = 0
	[int]$rowsImported = 0
	$sqlConn = $null
	try {
		$auditFiles = @(Get-SqlAuditFile -Folder $Folder)
		if (-not $auditFiles) {
			Write-LogMessage -Message "No audit files found in $Folder" `
				-LogFile $LogFile
			return
		}
		$auditsToProcess = @($auditFiles.AuditGuid | Sort-Object -Unique)
		Write-LogMessage -Message "$($auditFiles.Count) audit file(s) found in the $Folder" `
			-LogFile $LogFile
		Write-LogMessage -Message "$($auditsToProcess.Count) unique audit GUID(s) found" `
			-LogFile $LogFile

		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr
		$sqlConn.Open()

		$importStatesMap = Get-ImportState -SqlConn $sqlConn -AuditGuids $auditsToProcess

		foreach ($auditGuid in $auditsToProcess) {
			$importState = $null
			$res = $null
			if ($importStatesMap.TryGetValue($auditGuid, [ref]$importState)) {
				$res = Import-SqlAuditFile -SqlConn $sqlConn -Folder $Folder `
					-AuditGuid $auditGuid `
					-FileName $importState.FileName `
					-FileOffset $importState.AuditFileOffset
			}
			else {
				$res = Import-SqlAuditFile -SqlConn $sqlConn `
					-Folder $Folder `
					-AuditGuid $auditGuid
			}

			$rowProcessed += $res.RowProcessed
			$rowsImported += $res.RowsImported
		}
		Write-LogMessage -Message "$rowProcessed audit records processed" `
			-LogFile $LogFile
		Write-LogMessage -Message "$rowsImported audit records imported" `
			-LogFile $LogFile
	}
	finally {
		if ($null -ne $sqlConn) {
			$sqlConn.Dispose()
		}
	}
}
