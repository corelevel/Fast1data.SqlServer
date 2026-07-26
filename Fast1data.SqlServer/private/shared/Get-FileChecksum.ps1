<#
.SYNOPSIS
Calculates the checksum of a file.

.DESCRIPTION
Calculates and returns the SHA-256 checksum used to detect changes to migration
scripts after they have been executed.

.PARAMETER File
Specifies the file whose SHA-256 checksum is calculated.
#>
function Get-FileChecksum {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$File
	)

	(Get-FileHash -Path $File -Algorithm SHA256).Hash
}
