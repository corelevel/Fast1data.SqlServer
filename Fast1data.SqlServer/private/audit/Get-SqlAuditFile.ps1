<#
.SYNOPSIS
Finds SQL Server Audit files in a local folder or SMB share.

.DESCRIPTION
Finds .sqlaudit files whose names match the SQL Server Audit naming convention
and returns objects containing the full file path and audit GUID.

On Windows, uses Get-ChildItem to enumerate files.
On Linux, uses smbclient to enumerate files on an SMB share.
Linux requires supplied credentials and smbclient in PATH. Discovery is
nonrecursive and interprets filenames only. Successful no-match listings emit
no objects; invalid requests and listing failures terminate before any results.
Temporary process PASSWD is restored on every Linux exit, including failures.
Serialize discovery calls within a host process. SQL Server reads the files
independently using its own service-account permissions.

.PARAMETER Folder
Specifies the folder containing SQL Server Audit files.
Supports local and UNC paths on Windows and UNC paths on Linux.

.PARAMETER Credential
Specifies the credentials used to access the SMB share.
Required on Linux and not used on Windows.

.OUTPUTS
PSCustomObject
Returns objects with the following properties:
	FileName - Full path to the SQL Server Audit file.
	AuditGuid - Audit GUID extracted from the filename.

.EXAMPLE
Get-SqlAuditFile -Folder 'C:\SQLAudit'

Lists SQL Server Audit files in a local folder on Windows.

.EXAMPLE
Get-SqlAuditFile -Folder '\\server\share\Audit'

Lists SQL Server Audit files on an SMB share using the current Windows user's credentials.

.EXAMPLE
Get-SqlAuditFile -Folder '\\server\share\Audit' -Credential $Credential

Lists SQL Server Audit files on an SMB share from Linux using the specified credentials.
#>
function Get-SqlAuditFile {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Folder,

		[PSCredential]$Credential
	)

	# Prefix: Nonempty; may contain underscores and spaces.
	# GUID: Hexadecimal GUID in standard 8-4-4-4-12 layout; either letter case.
	# Sequence: Nonempty digits; no conversion, ordering, or range rule.
	# Ticks: Nonempty digits; no conversion, timestamp validation, or range rule.
	# Extension: Existing lowercase `.sqlaudit` baseline; no new case-support promise.
	# FileName: Candidate's complete full path.
	# AuditGuid: GUID value extracted by the authoritative filename rule.
	$regex = '^(?<AuditName>.+?)_(?<AuditGuid>[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})_(?<Sequence>\d+)_(?<Ticks>\d+)\.sqlaudit$'

	# Complete the listing before publishing any discovery results.
	$entries = @(Get-SqlAuditFileEntry -Folder $Folder -Credential $Credential)
	foreach ($entry in $entries) {
		if ($entry.Name -match $regex) {
			[PSCustomObject]@{
				FileName = $entry.FullName
				AuditGuid = [Guid]$Matches.AuditGuid
			}
		}
	}
}
