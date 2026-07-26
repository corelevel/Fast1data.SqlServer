Set-StrictMode -Version Latest

. "$PSScriptRoot\private\shared\Get-RuntimeIdentifier.ps1"
. "$PSScriptRoot\private\shared\Import-SqlClientLib.ps1"

Import-SqlClientLib

$privateScripts = Get-ChildItem -LiteralPath "$PSScriptRoot\private" `
	-Filter '*.ps1' -File -Recurse |
	Where-Object {
		$_.Name -notin @(
			'Get-RuntimeIdentifier.ps1'
			'Import-SqlClientLib.ps1'
		)
	}

$publicScripts = Get-ChildItem -LiteralPath "$PSScriptRoot\public" `
	-Filter '*.ps1' -File

foreach ($script in @($privateScripts) + @($publicScripts)) {
	. $script.FullName
}

Export-ModuleMember -Function $publicScripts.BaseName
