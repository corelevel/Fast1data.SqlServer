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

	Remove-Item $dest -Recurse -Force -ErrorAction Ignore

	Copy-Item $source $dest -Recurse
}
