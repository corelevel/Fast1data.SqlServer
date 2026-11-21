BeforeDiscovery {
	$script:selectorCases = @(
		foreach ($os in @('Windows', 'Linux')) {
			@{ OS = $os; OSArch = 'X64'; ProcessArch = 'X64'; Accepted = $true }
			foreach ($arch in [Enum]::GetNames([System.Runtime.InteropServices.Architecture]) | Where-Object { $_ -ne 'X64' }) {
				@{ OS = $os; OSArch = $arch; ProcessArch = 'X64'; Accepted = $false }
				@{ OS = $os; OSArch = $arch; ProcessArch = $arch; Accepted = $false }
				@{ OS = $os; OSArch = 'X64'; ProcessArch = $arch; Accepted = $false }
			}
		}
		foreach ($os in @('macOS', 'Unknown')) {
			foreach ($arch in @('X64', 'Arm64')) {
				@{ OS = $os; OSArch = $arch; ProcessArch = 'X64'; Accepted = $false }
			}
		}
	)
	$script:importCases = @(
		foreach ($entry in @('psd1', 'psm1')) {
			foreach ($arch in @('X64', 'Arm64')) {
				foreach ($stale in @($false, $true)) {
					foreach ($preload in @($false, $true)) {
						@{ OS = 'macOS'; OSArch = $arch; ProcessArch = $arch; Entry = $entry; Stale = $stale; Warm = $preload }
					}
				}
			}
			@{ OS = 'Unknown'; OSArch = 'X64'; ProcessArch = 'X64'; Entry = $entry; Stale = $false; Warm = $false }
			foreach ($os in @('Windows', 'Linux')) {
				foreach ($pair in @(@('Arm64', 'X64'), @('X86', 'X64'), @('X64', 'Arm64'), @('X64', 'X86'))) {
					@{ OS = $os; OSArch = $pair[0]; ProcessArch = $pair[1]; Entry = $entry; Stale = $false; Warm = $false }
				}
			}
		}
	)
}

BeforeAll {
	$script:distribution = Split-Path -Parent $PSScriptRoot
	Set-Content -LiteralPath (Join-Path $TestDrive '.runtime-test-parent') -Value 'disposable runtime scenarios'
	function Invoke-RuntimeWorker {
		param ([string]$OS, [string]$OSArch, [string]$ProcessArch, [string]$Entry = 'Selector', [bool]$Stale = $false, [bool]$Warm = $false)
		$arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'fixtures/Invoke-RuntimeSupportScenario.ps1'), '-DistributionRoot', $script:distribution,
			'-FixtureRoot', (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))), '-OperatingSystem', $OS, '-OSArchitecture', $OSArch, '-ProcessArchitecture', $ProcessArch, '-EntryPoint', $Entry)
		if ($Stale) {
			$arguments += '-StaleBundle'
		}
		if ($Warm) {
			$arguments += '-Preload'
		}
		$output = @(& (Join-Path $PSHOME 'pwsh') @arguments 2>&1)
		$workerExit = $LASTEXITCODE
		$records = @($output | Where-Object { "$_".StartsWith('RUNTIME_SUPPORT_RESULT:') })
		$records | Should -HaveCount 1 -Because ($output -join "`n")
		$result = $records[0].ToString().Substring('RUNTIME_SUPPORT_RESULT:'.Length) | ConvertFrom-Json
		$workerExit | Should -Be 0 -Because $result.HarnessError
		$result.Complete | Should -BeTrue
		if ($Warm) {
			$result.PreloadedTypes | Should -HaveCount 2
		}
		$result
	}
	function Assert-PlatformRejection {
		param ($Result)
		$Result.Error | Should -Match 'Unsupported.*(operating system|platform|architecture)'
		$Result.Error | Should -Match 'x64 Windows.*win-x64'
		$Result.Error | Should -Match 'x64 Linux.*linux-x64'
		$Result.Error | Should -Not -Match 'Missing.*dll|Cannot initialize.*dll|Rebuild dependencies|build/build.ps1'
		if ($Result.OperatingSystem -in @('macOS', 'Unknown')) {
			$Result.Error | Should -Match 'Unsupported operating system'
		}
		$Result.Rid | Should -BeNullOrEmpty
		@($Result.Probes) | Should -HaveCount 0
	}
}

Describe 'Simulated native runtime selector facts' {
	It '<OS> OS=<OSArch> process=<ProcessArch> selects only a matching retained runtime' -ForEach $script:selectorCases {
		$result = Invoke-RuntimeWorker -OS $OS -OSArch $OSArch -ProcessArch $ProcessArch
		if ($Accepted) {
			$result.Error | Should -BeNullOrEmpty
			$expected = 'linux-x64'
			if ($OS -eq 'Windows') {
				$expected = 'win-x64'
			}
			$result.Rid | Should -BeExactly $expected
		}
		else {
			Assert-PlatformRejection $result
		}
	}
}

Describe 'Simulated unsupported root imports in fresh processes' {
	It '<Entry> rejects <OS> OS=<OSArch> process=<ProcessArch> stale=<Stale> preload=<Warm> before all downstream probes' -ForEach $script:importCases {
		$result = Invoke-RuntimeWorker -OS $OS -OSArch $OSArch -ProcessArch $ProcessArch -Entry $Entry -Stale $Stale -Warm $Warm
		Assert-PlatformRejection $result
	}
}
