$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$targetFramework = ([xml](Get-Content -LiteralPath "$PSScriptRoot\SqlClientLoader.csproj" -Raw)).Project.PropertyGroup.TargetFramework

$rids = @(
	'win-x64',
	'linux-x64',
	'osx-x64'
)

foreach ($rid in $rids) {
	dotnet publish `
		$PSScriptRoot\SqlClientLoader.csproj `
		-c Release `
		-r $rid `
		--self-contained false

	if ($LASTEXITCODE -ne 0) {
		throw "dotnet publish failed for $rid"
	}

	$source = Join-Path $PSScriptRoot "bin/Release/$targetFramework/$rid/publish"
	$dest = Join-Path $PSScriptRoot "../Fast1data.SqlServer/lib/$rid"
	$dest = [System.IO.Path]::GetFullPath($dest)
	$libraryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../Fast1data.SqlServer/lib'))
	if ([System.IO.Directory]::GetParent($dest).FullName -ne $libraryRoot -or
		[System.IO.Path]::GetFileName($dest) -cne $rid) {
		throw "Refusing to clean unexpected dependency path: $dest"
	}
	$requiredAssemblies = @('Microsoft.Data.SqlClient.dll', 'Microsoft.SqlServer.TransactSql.ScriptDom.dll')
	foreach ($assembly in $requiredAssemblies) {
		if (-not (Test-Path -LiteralPath (Join-Path $source $assembly) -PathType Leaf)) {
			throw "Missing published dependency '$assembly' for '$rid'. Rebuild dependencies."
		}
	}
	if (Test-Path -LiteralPath $dest) {
		Remove-Item -LiteralPath $dest -Recurse -Force
	}
	Copy-Item -LiteralPath $source -Destination $dest -Recurse
	foreach ($assembly in $requiredAssemblies) {
		if (-not (Test-Path -LiteralPath (Join-Path $dest $assembly) -PathType Leaf)) {
			throw "Missing copied dependency '$assembly' for '$rid'. Rebuild dependencies."
		}
	}
}
