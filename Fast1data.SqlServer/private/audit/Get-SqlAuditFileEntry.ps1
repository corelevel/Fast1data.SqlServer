<#
.SYNOPSIS
Lists file candidates without interpreting audit filenames.

.DESCRIPTION
Windows performs literal, nonrecursive enumeration using the current identity.
Linux requires smbclient and listing credentials. A successful empty listing
emits no candidates; prerequisite, enumeration and process failures terminate.
Linux borrows process PASSWD only for listing and restores its exact prior state
in finally. Calls must be serialized within the host process. Native diagnostics
are captured and sanitized; SQL Server file access remains independent.

.PARAMETER Folder
Windows local/UNC directory; Linux UNC server/share with optional nested directory. Preserve directory-name spaces. Invalid requests terminate.

.PARAMETER Credential
Required and not `PSCredential.Empty` on Linux; unused on Windows. Used only for listing.

.OUTPUTS
Name: Basename from a genuine file entry, with filename spaces preserved. May be an invalid audit name.
FullName: Full path to that file in the requested directory. Windows uses the enumerated full path; Linux reconstructs the UNC file path.
#>
function Get-SqlAuditFileEntry {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Folder,
		[PSCredential]$Credential
	)

	if ($IsWindows) {
		Get-ChildItem -LiteralPath $Folder -File -ErrorAction Stop | ForEach-Object {
			[PSCustomObject]@{
				Name = $_.Name;
				FullName = $_.FullName
			}
		}
		return
	}
	if (-not $IsLinux) {
		throw 'Unsupported operating system. Audit discovery supports Windows and Linux.'
	}
	if (-not $Credential -or $Credential -eq [PSCredential]::Empty) {
		throw 'Credential is required for Linux and cannot be empty.'
	}
	if (-not (Get-Command smbclient -ErrorAction SilentlyContinue)) {
		throw 'smbclient is not installed or not available in PATH.'
	}

	if ($Folder -notmatch '^(?:\\\\|//)(?<Server>[^\\/\s:]+)[\\/](?<Share>[^\\/]+)(?<Directory>(?:[\\/][^\\/]+)*?)[\\/]*$' -or
		[string]::IsNullOrWhiteSpace($Matches.Share)) {
		throw 'Specify a UNC server/share folder for Linux audit discovery, for example \\server\share\nested folder.'
	}
	$share = "//$($Matches.Server)/$($Matches.Share)"
	$directory = $Matches.Directory.TrimStart('\', '/') -replace '\\', '/'
	$smbArgs = @($share, '-U', $Credential.UserName, '-c', 'ls')
	if ($directory) {
		$smbArgs += @('-D', $directory)
	}
	$PSNativeCommandUseErrorActionPreference = $false
	$invocationFailure = $null
	$password = $Credential.GetNetworkCredential().Password
	# Prior presence: Remember whether process `PASSWD` existed before discovery.
	$hadPasswd = Test-Path Env:PASSWD
	# Prior value: Preserve exactly for restoration; never log it.
	$priorPasswd = [Environment]::GetEnvironmentVariable('PASSWD', 'Process')
	try {
		# Temporary value: Supplied password; only available to the listing operation and its child.
		$env:PASSWD = $password
		$output = @(& smbclient @smbArgs *>&1)
		$exitCode = $LASTEXITCODE
	}
	catch {
		$invocationFailure = $_.Exception.Message
	}
	finally {
		if ($hadPasswd) {
			$env:PASSWD = $priorPasswd
		}
		else {
			Remove-Item Env:PASSWD -ErrorAction SilentlyContinue
		}
	}

	# Construct a fresh error after cleanup; never retain the native ErrorRecord,
	# target object or inner exception in the error exposed to the caller.
	if ($null -ne $invocationFailure -or $exitCode -ne 0) {
		if ($null -ne $invocationFailure) {
			$message = "smbclient invocation failed: $invocationFailure"
			$errorId = 'SqlAuditSmbInvocationFailed'
			$category = [System.Management.Automation.ErrorCategory]::OpenError
		}
		else {
			$message = "smbclient failed (exit code $exitCode): $($output -join "`n")"
			$errorId = 'SqlAuditSmbListingFailed'
			$category = [System.Management.Automation.ErrorCategory]::ReadError
		}
		foreach ($secret in (@($password, $priorPasswd) | Sort-Object Length -Descending)) {
			if (-not [string]::IsNullOrEmpty($secret)) {
				$message = $message.Replace($secret, '[REDACTED]')
			}
		}
		$errorRecord = [System.Management.Automation.ErrorRecord]::new(
			[InvalidOperationException]::new($message), $errorId, $category, $null)
		$PSCmdlet.ThrowTerminatingError($errorRecord)
	}

	# Match complete ls rows: basename, DOS attributes, byte size, timestamp.
	# The two leading spaces are smbclient's indentation, not part of the name.
	$rowPattern = '^  (?<Name>.+?)\s+(?<Attributes>[A-Z]+)\s+\d+\s+[A-Za-z]{3}\s+[A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4}\s*$'
	foreach ($line in $output) {
		if ($line.ToString() -cmatch $rowPattern -and $Matches.Attributes -cnotmatch 'D') {
			$name = $Matches.Name
			[PSCustomObject]@{
				Name = $name;
				FullName = "$($Folder.TrimEnd('\', '/'))\$name"
			}
		}
	}
}
