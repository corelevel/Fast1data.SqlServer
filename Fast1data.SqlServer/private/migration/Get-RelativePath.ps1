<#
.SYNOPSIS
Gets a path relative to another path.

.DESCRIPTION
Returns Path relative to RelativeTo. Migration processing uses the result as
the script name stored in migration history.

.PARAMETER RelativeTo
Specifies the base directory from which the relative path is calculated.

.PARAMETER Path
Specifies the target path to convert to a relative path.
#>
function Get-RelativePath {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$RelativeTo,

		[Parameter(Mandatory)]
		[string]$Path
	)
	[System.IO.Path]::GetRelativePath($RelativeTo, $Path)
}
