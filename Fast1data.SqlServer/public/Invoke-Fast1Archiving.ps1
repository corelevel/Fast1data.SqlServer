<#
.SYNOPSIS
Archives and purges configured SQL Server tables.

.DESCRIPTION
Runs the configured archiving process for a table group. The process can copy
eligible rows from source tables to archive tables, purge source rows in
batches, resume incomplete work, and write progress messages to a log file.

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
