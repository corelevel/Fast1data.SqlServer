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

	$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

	switch ($true) {
		$IsWindows {
			switch ($architecture) {
				([System.Runtime.InteropServices.Architecture]::X64) { return 'win-x64' }
				default { throw "Unsupported Windows architecture: $architecture" }
			}
		}
		$IsLinux {
			switch ($architecture) {
				([System.Runtime.InteropServices.Architecture]::X64) { return 'linux-x64' }
				default { throw "Unsupported Linux architecture: $architecture" }
			}
		}
		$IsMacOS {
			switch ($architecture) {
				([System.Runtime.InteropServices.Architecture]::X64) { return 'osx-x64' }
				default { throw "Unsupported macOS architecture: $architecture" }
			}
		}
		default {
			throw 'Unsupported operating system'
		}
	}
}
