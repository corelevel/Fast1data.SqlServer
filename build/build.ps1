$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$targetFramework = ([xml](Get-Content -LiteralPath "$PSScriptRoot\SqlClientLoader.csproj" -Raw)).Project.PropertyGroup.TargetFramework

$rids = @(
	'win-x64',
	'linux-x64'
)

$libraryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../Fast1data.SqlServer/lib'))
$obsoleteDestination = [System.IO.Path]::GetFullPath((Join-Path $libraryRoot 'osx-x64'))
if ([System.IO.Directory]::GetParent($obsoleteDestination).FullName -ne $libraryRoot -or
	[System.IO.Path]::GetFileName($obsoleteDestination) -cne 'osx-x64') {
	throw "Refusing to clean unexpected obsolete dependency path: $obsoleteDestination"
}
if (Test-Path -LiteralPath $obsoleteDestination) {
	Remove-Item -LiteralPath $obsoleteDestination -Recurse -Force
}

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

$actualRids = @(Get-ChildItem -LiteralPath $libraryRoot -Directory | Select-Object -ExpandProperty Name)
if ($actualRids.Count -ne $rids.Count -or @($actualRids | Where-Object { $_ -cnotin $rids }).Count -gt 0) {
	throw "Unexpected source runtime directories: $($actualRids -join ', '). Expected exactly: $($rids -join ', ')."
}
