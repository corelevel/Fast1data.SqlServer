<#
.SYNOPSIS
Writes a formatted Fast1 log message.

.DESCRIPTION
Writes informational messages to the verbose stream and warnings to the warning
stream.

.PARAMETER Message
Specifies the log message text.

.PARAMETER Level
Specifies the logging level. Valid values are Verbose and Warning. The default is Verbose.
#>

function Write-LogMessage {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Message,

		[ValidateSet('Warning', 'Verbose')]
		[string]$Level = 'Verbose'
	)

	$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
	$line = "[$timestamp] [$Level] $Message"

	if ($Level -eq 'Warning') {
		Write-Warning $line
	}
	else {
		Write-Verbose $line
	}
}
