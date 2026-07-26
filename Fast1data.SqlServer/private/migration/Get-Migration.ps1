<#
.SYNOPSIS
Gets the configured migration scripts for a phase.

.DESCRIPTION
Reads a migration.json file, selects the requested phase by its exact property
name, and returns its script paths using forward slashes as portable separators.

.PARAMETER ConfigFile
Specifies the path to the migration.json configuration file.

.PARAMETER Phase
Specifies the migration phase whose script list is returned.
#>
function Get-Migration {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConfigFile,

		[Parameter(Mandatory)]
		[string]$Phase
	)

	$json = Get-Content -LiteralPath $ConfigFile -Raw |
		ConvertFrom-Json

	$phaseProperty = $json.PSObject.Properties[$Phase]

	if ($null -eq $phaseProperty) {
		throw "Migration phase not found: $Phase"
	}

	$phaseProperty.Value.scripts |
		ForEach-Object { $_.Replace('\', '/') }
}
