<#
.SYNOPSIS
Initializes a managed DLL from this distribution's runtime bundle.

.DESCRIPTION
Validates the contained filename and selected asset on every call, including reuse.
Loaded assemblies must match the bundled name, version, culture and public key token.
Cold loads must originate in this bundle. All requested types must be available;
there is no library allowlist, source fallback, or success-stream output.

.PARAMETER DllName
One managed DLL filename, without directory components or wildcard characters.

.PARAMETER RequiredTypeName
Optional case-sensitive fully qualified type names required from the assembly.
#>
function Import-RequiredLibrary {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$DllName,

		[ValidateNotNullOrEmpty()]
		[string[]]$RequiredTypeName = @()
	)

	if ([System.IO.Path]::IsPathRooted($DllName) -or $DllName -match '[\x00-\x1f<>:"/\\|?*\[\]]' -or
		[System.IO.Path]::GetExtension($DllName) -ine '.dll' -or
		[string]::IsNullOrWhiteSpace([System.IO.Path]::GetFileNameWithoutExtension($DllName))) {
		throw [System.ArgumentException]::new('DllName must be a single contained DLL filename without paths or wildcards.', 'DllName')
	}
	foreach ($typeName in $RequiredTypeName) {
		if ([string]::IsNullOrWhiteSpace($typeName)) {
			throw [System.ArgumentException]::new('RequiredTypeName must contain nonempty type names.', 'RequiredTypeName')
		}
	}
	$rid = Get-RuntimeIdentifier
	$bundlePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../../lib/$rid"))
	$expectedPath = [System.IO.Path]::GetFullPath((Join-Path $bundlePath $DllName))
	try {
		if ([System.IO.Path]::GetDirectoryName($expectedPath) -cne $bundlePath -or
			-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
			throw [System.IO.FileNotFoundException]::new('The selected bundled managed library is missing.')
		}
		$expectedIdentity = [System.Reflection.AssemblyName]::GetAssemblyName($expectedPath)
		if ($expectedIdentity.Name -ine [System.IO.Path]::GetFileNameWithoutExtension($DllName)) {
			throw [System.BadImageFormatException]::new('Bundled assembly name does not match the requested filename.')
		}
		$assembly = $null
		foreach ($loaded in [AppDomain]::CurrentDomain.GetAssemblies()) {
			$identity = $loaded.GetName()
			if ($identity.Name -ine $expectedIdentity.Name) {
				continue
			}
			if ($identity.FullName -ine $expectedIdentity.FullName) {
				throw [System.IO.FileLoadException]::new('An incompatible assembly with the requested name is already loaded; use a fresh process.')
			}
			$assembly = $loaded
		}
		if ($null -eq $assembly) {
			$assembly = [System.Reflection.Assembly]::LoadFrom($expectedPath)
			if ($assembly.GetName().FullName -ine $expectedIdentity.FullName -or
				[System.IO.Path]::GetFullPath($assembly.Location) -cne $expectedPath) {
				throw [System.IO.FileLoadException]::new('Cold assembly resolution did not match the selected bundle.')
			}
		}
		foreach ($typeName in $RequiredTypeName) {
			if ($null -eq $assembly.GetType($typeName, $false, $false)) {
				throw [System.TypeLoadException]::new('A requested type is unavailable from the selected managed assembly.')
			}
		}
	}
	catch {
		throw [System.InvalidOperationException]::new(
			"Cannot initialize '$DllName' for runtime '$rid' at '$expectedPath'. Rebuild dependencies with build/build.ps1 and use a fresh process.",
			$_.Exception
		)
	}
}
