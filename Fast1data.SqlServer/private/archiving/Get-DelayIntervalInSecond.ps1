<#
.SYNOPSIS
Converts an archiving delay interval to seconds.

.DESCRIPTION
Parses an archiving delay in HH:mm:ss format and returns its total number of
seconds.

.PARAMETER DelayInterval
Specifies the delay interval in HH:mm:ss format.
#>
function Get-DelayIntervalInSecond {
	param (
		[Parameter(Mandatory)]
		[string]$DelayInterval
	)

	$delay = [datetime]::ParseExact(
		"01010001 $DelayInterval",
		'ddMMyyyy HH:mm:ss',
		$null
	)
	$midnight = [datetime]::ParseExact(
		'01010001 00:00:00',
		'ddMMyyyy HH:mm:ss',
		$null
	)

	$delay.Subtract($midnight).TotalSeconds
}
