BeforeDiscovery {
	$script:tuples = foreach ($loading in @('L1', 'L2', 'L3', 'L4', 'L5')) {
		foreach ($order in @('ARM', 'AMR', 'RAM', 'RMA', 'MAR', 'MRA')) {
			@{ Loading = $loading; Order = $order }
		}
	}
}

BeforeAll {
	$script:distributionRoot = Split-Path -Parent $PSScriptRoot
	$script:worker = Join-Path $PSScriptRoot 'fixtures/Invoke-SharedHelperScenario.ps1'
	$script:observed = [System.Collections.Generic.HashSet[string]]::new()
	$script:results = [System.Collections.Generic.List[object]]::new()
}

Describe 'Isolated shared-helper import and operation matrix' {
	It '<Loading> / <Order> retains the selected distribution contract' -ForEach $script:tuples {
		$output = @(& (Join-Path $PSHOME 'pwsh') -NoProfile -File $script:worker -DistributionRoot $script:distributionRoot -LoadingScenario $Loading -OperationOrder $Order 2>&1)
		$script:workerExit = $LASTEXITCODE
		$records = @($output | Where-Object { "$_".StartsWith('SHARED_HELPER_RESULT:') })
		$records | Should -HaveCount 1 -Because ($output -join "`n")
		$result = $records[0].ToString().Substring('SHARED_HELPER_RESULT:'.Length) | ConvertFrom-Json
		$script:workerExit | Should -Be 0 -Because ($result.Errors -join "`n")
		$result.Root | Should -Be $script:distributionRoot
		$result.Loading | Should -Be $Loading
		$result.Order | Should -Be $Order
		$result.Total | Should -Be 136
		($result.Passed + $result.Skipped) | Should -Be $result.Total
		$result.Failed | Should -Be 0
		$result.UnexpectedSkipped | Should -Be 0
		$script:observed.Add("$Loading/$Order") | Should -BeTrue
		$script:results.Add($result)
	}

	AfterAll {
		$script:observed.Count | Should -Be 30
		Write-Information ('SHARED_HELPER_MATRIX:' + ($script:results | ConvertTo-Json -Depth 8 -Compress)) -InformationAction Continue
	}
}
