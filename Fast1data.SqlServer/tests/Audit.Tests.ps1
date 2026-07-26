BeforeAll {
	$projectRoot = Split-Path -Parent $PSScriptRoot
	$modulePath = Join-Path $projectRoot 'Fast1data.SqlServer.psd1'
	$script:auditSourcePath = Join-Path $projectRoot 'Private\Audit'
	$script:tablesPath = Join-Path $projectRoot 'schema\Audit\tables.sql'
	$script:sprocsPath = Join-Path $projectRoot 'schema\Audit\sprocs.sql'

	Import-Module $modulePath -Force
}

Describe 'Fast1data.SqlServer module' {
	It 'imports and exports Invoke-Fast1Audit' {
		$command = Get-Command Invoke-Fast1Audit -Module Fast1data.SqlServer

		$command | Should -Not -BeNullOrEmpty
	}

	It 'rejects a folder that does not exist' {
		$missingFolder = Join-Path $TestDrive 'missing'

		{
			Invoke-Fast1Audit -ConnStr 'unused' -Folder $missingFolder
		} | Should -Throw
	}
}

Describe 'SQL audit file discovery' {
	It 'parses a valid SQL audit filename' {
		$folder = Join-Path $TestDrive 'valid-audit-files'
		$null = New-Item -Path $folder -ItemType Directory
		$auditGuid = [guid]'615e3b8a-9980-4739-89dd-b8ca9d93c36e'
		$fileName = "fast1_audit_00_${auditGuid}_0_134289496418640003.sqlaudit"
		$filePath = Join-Path $folder $fileName
		$null = New-Item -Path $filePath -ItemType File

		$result = InModuleScope 'Fast1data.SqlServer' -Parameters @{ Folder = $folder } {
			Get-SqlAuditFile -Folder $Folder
		}

		$result | Should -HaveCount 1
		$result.AuditGuid | Should -Be $auditGuid
		$result.BaseFileName | Should -Be 'fast1_audit_00'
		$result.FileName | Should -Be $filePath
	}

	It 'ignores a filename that does not follow the SQL audit naming convention' {
		$folder = Join-Path $TestDrive 'invalid-audit-files'
		$null = New-Item -Path $folder -ItemType Directory
		$null = New-Item -Path (Join-Path $folder 'invalid.sqlaudit') -ItemType File

		$result = InModuleScope 'Fast1data.SqlServer' -Parameters @{ Folder = $folder } {
			Get-SqlAuditFile -Folder $Folder
		}

		$result | Should -BeNullOrEmpty
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
