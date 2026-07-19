$rids = @(
	'win-x64',
	'linux-x64',
	'osx-x64',
	'osx-arm64'
)

foreach ($rid in $rids) {
	dotnet publish `
		$PSScriptRoot\SqlClientLoader.csproj `
		-c Release `
		-r $rid `
		--self-contained false

	$source = Join-Path $PSScriptRoot "\bin\Release\net8.0\$rid\publish"
	$dest = Join-Path $PSScriptRoot "..\lib\$rid"

	Remove-Item $dest -Recurse -Force -ErrorAction Ignore

	Copy-Item $source $dest -Recurse
}