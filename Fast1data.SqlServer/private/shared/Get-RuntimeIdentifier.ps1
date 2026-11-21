<#
.SYNOPSIS
Returns the runtime identifier for the current platform.

.DESCRIPTION
Maps the current operating system and processor architecture to a runtime
identifier supported by the bundled Microsoft.Data.SqlClient libraries.
#>
function Get-RuntimeIdentifier {
	[CmdletBinding()]
	[OutputType([string])]
	param()

	$supportedPlatforms = 'Supported platforms are x64 Windows (win-x64) and x64 Linux (linux-x64).'
	$operatingSystem = switch ($true) {
		$IsWindows {
			'Windows'
		}
		$IsLinux {
			'Linux'
		}
		default {
			throw "Unsupported operating system. $supportedPlatforms"
		}
	}
	$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
	if ($architecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
		throw "Unsupported $operatingSystem OS architecture: $architecture. $supportedPlatforms"
	}
	$processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
	if ($processArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
		throw "Unsupported $operatingSystem process architecture: $processArchitecture. $supportedPlatforms"
	}
	if ($operatingSystem -eq 'Windows') {
		return 'win-x64'
	}
	return 'linux-x64'
}
