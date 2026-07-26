<#
.SYNOPSIS
Writes a formatted Fast1 Audit log message.

.DESCRIPTION
Writes informational messages to the verbose stream, warnings to the warning
stream, and errors to the error stream. When LogFile is supplied, the formatted
message is also appended to that file.

.PARAMETER Message
Specifies the text of the log message.

.PARAMETER LogFile
Specifies an optional file to which the formatted message is appended.

.PARAMETER Level
Specifies the message level. Valid values are Info, Warning, and Error.
#>
function Write-LogMessage {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Message,

		[string]$LogFile,

		[ValidateSet('Info','Warning','Error')]
		[string]$Level = 'Info'
	)

	$line = "$((Get-Date).ToString('[MM/dd/yy HH:mm:ss.ff]')) [$Level] $Message"

	if ($Level -eq 'Warning') {
		Write-Warning $line
	}
	elseif ($Level -eq 'Error') {
		Write-Error $line
	}
	else {
		Write-Verbose $line
	}

	if ($LogFile) {
		Add-Content -Path $LogFile -Value $line
	}
}
