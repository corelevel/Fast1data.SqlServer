<#
.SYNOPSIS
Retrieves saved import state for audit GUIDs.

.DESCRIPTION
Calls dbo.stp_get_import_state with the supplied audit GUIDs and returns a
dictionary keyed by audit GUID. Each value contains the last file name and file
offset saved for that audit.

.PARAMETER SqlConn
Specifies an open Microsoft.Data.SqlClient connection to the Fast1 Audit
database.

.PARAMETER AuditGuids
Specifies the audit GUIDs for which import state is requested.
#>
function Get-ImportState {
	[CmdletBinding()]
	[OutputType([System.Collections.Generic.Dictionary[System.Guid, System.Object]])]
	param (
		[Parameter(Mandatory)]
		[Microsoft.Data.SqlClient.SqlConnection]$SqlConn,

		[Parameter(Mandatory)]
		[guid[]]$AuditGuids
	)

	$sqlCmd = $null
	$sqlReader = $null

	try {
		$tvp = [System.Data.DataTable]::new()
		[void]$tvp.Columns.Add('value', [Guid])

		foreach ($guid in $AuditGuids) {
			[void]$tvp.Rows.Add($guid)
		}

		$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_get_import_state', $SqlConn)
		$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
		$p = $sqlCmd.Parameters.Add('@audit_guids', [System.Data.SqlDbType]::Structured)
		$p.TypeName = 'dbo.guid_array'
		$p.Value = $tvp
		$sqlReader = $sqlCmd.ExecuteReader()

		$importStatesMap = [System.Collections.Generic.Dictionary[System.Guid, System.Object]]::new()

		while ($sqlReader.Read()) {
			$importStatesMap[$sqlReader['audit_guid']] = [PSCustomObject]@{
				FileName = $sqlReader['file_name']
				AuditFileOffset = $sqlReader['audit_file_offset']
			}
		}

		$importStatesMap
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
