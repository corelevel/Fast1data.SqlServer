BeforeAll {
	$projectRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $projectRoot 'Fast1data.SqlServer.psd1'
	$script:auditSourcePath = Join-Path $projectRoot 'private/audit'
	$script:tablesPath = Join-Path $projectRoot 'schema/audit/tables.sql'
	$script:sprocsPath = Join-Path $projectRoot 'schema/audit/sprocs.sql'

	Import-Module $modulePath -Force
}

Describe 'Fast1data.SqlServer module' {
	It 'retains exactly three public exports and keeps discovery helpers private' {
		$exports = @(Get-Command -Module Fast1data.SqlServer | Select-Object -ExpandProperty Name | Sort-Object)
		$exports -join ',' | Should -Be 'Invoke-Fast1Archiving,Invoke-Fast1Audit,Invoke-Fast1Migration'
		Get-Command Get-SqlAuditFile,Get-SqlAuditFileEntry -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
		InModuleScope Fast1data.SqlServer {
			Get-Command Get-SqlAuditFileEntry | Should -Not -BeNullOrEmpty
		}
	}

	It 'preserves audit verbose output when the archiving model is imported after shared helpers' {
		InModuleScope Fast1data.SqlServer {
			# Packaging can enumerate archiving scripts after the shared scripts.
			Import-Module (Join-Path $PSScriptRoot '../private/archiving/ArchivingModel.psm1') -ErrorAction Stop
			Mock Get-SqlAuditFile {
				@()
			}

			$messages = @(Invoke-Fast1Audit -ConnStr 'unused' -Folder 'unused' -Verbose 4>&1)

			$messages | Should -HaveCount 1
			$messages[0].Message | Should -BeLike '*No audit files found*'
		}
	}
}

Describe 'PowerShell and SQL contracts' {
	It 'uses audit_file_offset consistently' {
		$moduleSource = (
			Get-ChildItem -LiteralPath $script:auditSourcePath -Filter '*.ps1' |
				ForEach-Object {
					Get-Content -LiteralPath $_.FullName -Raw
				}
		) -join "`n"
		$tablesSource = Get-Content -LiteralPath $script:tablesPath -Raw
		$sprocsSource = Get-Content -LiteralPath $script:sprocsPath -Raw

		$moduleSource | Should -Match 'audit_file_offset'
		$tablesSource | Should -Match 'audit_file_offset'
		$sprocsSource | Should -Match 'audit_file_offset'

		$moduleSource | Should -Not -Match 'audit_record_offset'
		$tablesSource | Should -Not -Match 'audit_record_offset'
		$sprocsSource | Should -Not -Match 'audit_record_offset'
	}

	It 'returns the result columns expected by PowerShell' {
		$moduleSource = (
			Get-ChildItem -LiteralPath $script:auditSourcePath -Filter '*.ps1' |
				ForEach-Object {
					Get-Content -LiteralPath $_.FullName -Raw
				}
		) -join "`n"
		$sprocsSource = Get-Content -LiteralPath $script:sprocsPath -Raw

		$moduleSource | Should -Match "\['row_processed'\]"
		$moduleSource | Should -Match "\['rows_imported'\]"
		$sprocsSource | Should -Match 'row_processed'
		$sprocsSource | Should -Match 'rows_imported'
	}
}
