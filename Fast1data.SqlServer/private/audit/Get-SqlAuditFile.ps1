<#
.SYNOPSIS
Finds SQL Server Audit files in a folder.

.DESCRIPTION
Finds .sqlaudit files whose names match the SQL Server Audit naming convention
and returns their paths, base names, and audit GUIDs.

.PARAMETER Folder
Specifies the folder containing the SQL Server Audit files.
#>
function Get-SqlAuditFile {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Folder
	)

	$regex = '^(?<AuditName>.+?)_(?<AuditGuid>[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})_(?<Sequence>\d+)_(?<Ticks>\d+)\.sqlaudit$'

	Get-ChildItem -Path $Folder -Filter '*.sqlaudit' -File | ForEach-Object {
		if ($_.Name -match $regex) {
			[PSCustomObject]@{
				DirectoryName = $_.DirectoryName
				FileName      = $_.FullName
				BaseFileName  = $Matches.AuditName
				AuditGuid     = [Guid]$Matches.AuditGuid
			}
		}
	}
}
