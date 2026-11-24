<#
.SYNOPSIS
Imports SQL Server Audit files into the Fast1 Audit database.

.DESCRIPTION
Discovers SQL Server Audit files in a folder, retrieves the saved import state
for each unique audit GUID, imports new records, and reports processed and
imported record counts through the verbose stream.

Discovery supports Windows local/UNC folders and Linux UNC shares. Linux
requires smbclient in PATH and supplied listing credentials. A successful
listing with no matching filenames returns without importing; invalid requests
and listing failures terminate. Linux restores prior process PASSWD on every
exit; serialize discovery in a host process. SQL Server reads audit contents
independently under its service account and needs its own file permissions.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the Fast1 Audit
database.

.PARAMETER Folder
Specifies the folder containing SQL Server Audit files.
Supports local and UNC paths on Windows and UNC paths on Linux.

.PARAMETER Credential
Specifies the credentials used to access the SMB share.
Required on Linux and not used on Windows.

.EXAMPLE
$connectionString = 'Server=sql01.example.com;Database=fast1_audit;' +
	'Integrated Security=True;Encrypt=True;TrustServerCertificate=False'
Invoke-Fast1Audit -ConnStr $connectionString `
	-Folder '\\audit-server\sql-audit' -Verbose

On Windows, imports audit files using the current Windows identity for discovery
and Windows authentication to SQL Server. Deploy the audit schema and grant the SQL login audit-read
permissions first. The SQL Server service account also needs read access to the
share. Use a SQL Server name matching a certificate trusted by the client.

.EXAMPLE
$connectionString = $env:FAST1_AUDIT_SQL_CONN_STR
$shareCredential = Get-Credential -UserName 'DOMAIN\audit-reader' -Message 'SMB share credentials'
Invoke-Fast1Audit -ConnStr $connectionString `
	-Folder '\\audit-server\sql-audit' -Credential $shareCredential -Verbose

On Linux, discovers audit files with smbclient in PATH and prompted SMB credentials.
First supply FAST1_AUDIT_SQL_CONN_STR through your secret store with the target audit
database, provisioned SQL authentication, Encrypt=True, and TrustServerCertificate=False.
Deploy the audit schema and grant the SQL login audit-read permissions first.
The SMB credentials are for discovery; the SQL Server service account needs its
own read access to the share, and the SQL Server certificate must be trusted by the client.
#>
function Invoke-Fast1Audit {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$Folder,

		[PSCredential]$Credential
	)

	[int]$rowProcessed = 0
	[int]$rowsImported = 0
	$sqlConn = $null
	$operationError = $null
	try {
		$auditFiles = @(Get-SqlAuditFile -Folder $Folder -Credential $Credential)
		if (-not $auditFiles) {
			Write-LogMessage -Message "No audit files found in $Folder"
			return
		}
		$auditsToProcess = @($auditFiles.AuditGuid | Sort-Object -Unique)
		Write-LogMessage -Message "$($auditFiles.Count) audit file(s) found in the $Folder"
		Write-LogMessage -Message "$($auditsToProcess.Count) unique audit GUID(s) found"

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
		Write-LogMessage -Message "$rowProcessed audit records processed"
		Write-LogMessage -Message "$rowsImported audit records imported"
	}
	catch {
		$operationError = $_
		throw
	}
	finally {
		Close-GenericSqlResource -Resources ([ordered]@{ Connection = $sqlConn }) -PrimaryError $operationError
	}
}
