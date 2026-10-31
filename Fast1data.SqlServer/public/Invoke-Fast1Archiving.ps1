<#
.SYNOPSIS
Archives and purges configured SQL Server tables.

.DESCRIPTION
Runs the configured archiving process for a table group. The process can copy
eligible rows from source tables to archive tables, purge source rows in
batches, resume incomplete work, and write progress messages to a log file.

One request owns initialization, effects, checkpoints, constraint restoration and
resource release. Copy/delete effects and checkpoints commit independently. A
failed checkpoint can leave durable effects with lagging recorded totals. Retry
the same group with stable configuration, no concurrent execution, and retained
incomplete state/working tables. Confirmed captured keys remain authoritative;
retry reconciles actual destination presence and tolerates already deleted rows.

Processing stops on a failed required transition. Cleanup attempts continue
independently. The original error remains primary; secondary cleanup contexts
are available at Exception.Data['Fast1Archiving.CleanupFailures']. Cleanup-only
errors terminate invocation, including after durable completion.

DisableFK affects inbound source child-table foreign keys. Restoration enables
them without validating historical rows or establishing trust. Failed restoration
blocks new purge/overall completion. Server outages or hard termination can
prevent restoration; inspect affected constraints before retrying. Configuration
and source databases must share an instance, and source tables require PKs.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the archiving
configuration database.

.PARAMETER GroupName
Specifies the configured table-group name to archive or purge.

.PARAMETER LogFile
Specifies an optional file to which archiving progress messages are appended.
#>
function Invoke-Fast1Archiving {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$GroupName,

		[string]$LogFile
	)

	Invoke-ArchivingProcess `
		-ConnStr $ConnStr `
		-GroupName $GroupName `
		-LogFile $LogFile
}
