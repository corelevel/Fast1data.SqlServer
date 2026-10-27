<#
.SYNOPSIS
Finds SQL Server Audit files in a local folder or SMB share.

.DESCRIPTION
Finds .sqlaudit files whose names match the SQL Server Audit naming convention
and returns objects containing the full file path and audit GUID.

On Windows, uses Get-ChildItem to enumerate files.
On Linux, uses smbclient to enumerate files on an SMB share.

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

	$regex = '^(?<AuditName>.+?)_(?<AuditGuid>[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})_(?<Sequence>\d+)_(?<Ticks>\d+)\.sqlaudit$'

	if ($IsWindows) {
		Get-ChildItem -LiteralPath $Folder -Filter '*.sqlaudit' -File -ErrorAction Stop | ForEach-Object {
			if ($_.Name -match $regex) {
				[PSCustomObject]@{
					FileName = $_.FullName
					AuditGuid = [Guid]$Matches.AuditGuid
				}
			}
		}
	}
	elseif ($IsLinux) {
		if (-not (Get-Command smbclient -ErrorAction SilentlyContinue)) {
			throw 'smbclient is not installed or not available in PATH'
		}
		if (-not $Credential -or $Credential -eq [PSCredential]::Empty) {
			throw 'Credential is required for Linux and cannot be empty'
		}

		$parts = $Folder.Trim().Trim('\', '/') -split '[\\/]+'
		if ($parts.Count -lt 2 -or
			[string]::IsNullOrWhiteSpace($parts[0]) -or
			[string]::IsNullOrWhiteSpace($parts[1])) {
			throw "Invalid UNC path: $Folder"
		}

		$share = "//$($parts[0])/$($parts[1])"
		$directory = ($parts | Select-Object -Skip 2) -join '/'

		$smbArgs = @(
			$share
			'-U', $Credential.UserName
			'-c', 'ls *.sqlaudit'
		)

		if ($directory) {
			$smbArgs += @('-D', $directory)
		}

		try {
			$env:PASSWD = $Credential.GetNetworkCredential().Password
			$output = @(& smbclient @smbArgs 2>&1 | ForEach-Object { $_.ToString() })
			$exitCode = $LASTEXITCODE
		}
		finally {
			Remove-Item Env:PASSWD -ErrorAction SilentlyContinue
		}

		if ($exitCode -ne 0) {
			throw "smbclient failed (exit code $exitCode):`n$($output -join "`n")"
		}

		# Extract filenames and GUIDs
		foreach ($line in $output) {
			if ($line -match '^\s*(.+?\.sqlaudit)\s+') {
				$name = $Matches[1]
				if ($name -match $regex) {
					[PSCustomObject]@{
						FileName = "$($Folder.TrimEnd('\', '/'))\$name"
						AuditGuid = [Guid]$Matches.AuditGuid
					}
				}
			}
		}
	}
	else {
		throw 'Unsupported operating system. This function only supports Windows and Linux'
	}
}
