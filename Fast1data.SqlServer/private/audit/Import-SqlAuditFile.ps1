<#
.SYNOPSIS
Imports SQL Server Audit files for one audit GUID.

.DESCRIPTION
Calls dbo.stp_import_audit_files for files matching an audit GUID. When a file
name and offset are supplied, importing resumes from that saved position. The
function returns the numbers of records processed and imported.

.PARAMETER SqlConn
Specifies an open Microsoft.Data.SqlClient connection to the Fast1 Audit
database.

.PARAMETER Folder
Specifies the folder containing the SQL Server Audit files.

.PARAMETER AuditGuid
Specifies the audit GUID whose files are imported.

.PARAMETER FileName
Specifies the audit file from which a resumed import starts.

.PARAMETER FileOffset
Specifies the saved offset in FileName from which a resumed import starts.
#>
function Import-SqlAuditFile {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[Microsoft.Data.SqlClient.SqlConnection]$SqlConn,

		[Parameter(Mandatory)]
		[string]$Folder,

		[Parameter(Mandatory)]
		[Guid]$AuditGuid,

		[string]$FileName = $null,
		[System.Nullable[long]]$FileOffset = $null
	)

	$sqlCmd = $null
	$sqlReader = $null
	$filePattern = Join-Path $Folder "*$AuditGuid*.sqlaudit"

	try {
		$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_import_audit_files', $SqlConn)
		$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
		$sqlCmd.Parameters.Add('@file_pattern', [System.Data.SqlDbType]::NVarChar, 260).Value = $filePattern
		if (-not [string]::IsNullOrEmpty($FileName) -and -not ($null -eq $FileOffset)) {
			$sqlCmd.Parameters.Add('@initial_file_name', [System.Data.SqlDbType]::NVarChar, 260).Value = $FileName
			$sqlCmd.Parameters.Add('@audit_file_offset', [System.Data.SqlDbType]::BigInt).Value = $FileOffset
		}
		$sqlReader = $sqlCmd.ExecuteReader()
		if ($sqlReader.Read()) {
			[PSCustomObject]@{
				RowProcessed = $sqlReader['row_processed']
				RowsImported = $sqlReader['rows_imported']
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
	}
}
