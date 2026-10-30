[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText',
    '',
    Justification = 'Dummy credentials used only in Pester tests.'
)]
param()

BeforeAll {
	Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fast1data.SqlServer.psd1') -Force
}

Describe 'Audit import from Windows' -Tag 'Windows' -Skip:(-not $IsWindows) {
	BeforeAll {
		$script:credential = [pscredential]::new('DOMAIN\audit reader',
			(ConvertTo-SecureString 'audit-test-password' -AsPlainText -Force))
	}

	BeforeEach {
		# Real filesystem discovery, including spaces and literal wildcard characters.
		$script:folder = Join-Path $TestDrive "audit files [literal] $([guid]::NewGuid())"
		$null = New-Item -Path $script:folder -ItemType Directory
	}

	It 'returns without connecting to SQL with <CredentialKind> credentials when the folder is empty' -ForEach @(
		@{ CredentialKind = 'missing' }
		@{ CredentialKind = 'empty' }
		@{ CredentialKind = 'supplied' }
	) {
		$arguments = @{}
		if ($CredentialKind -eq 'empty') {
			$arguments.Credential = [pscredential]::Empty
		}
		elseif ($CredentialKind -eq 'supplied') {
			$arguments.Credential = $script:credential
		}
		$messages = @(Invoke-Fast1Audit -ConnStr 'invalid connection string' `
			-Folder $script:folder @arguments -Verbose 4>&1)

		$messages | Should -HaveCount 1
		$messages[0].Message | Should -BeLike '*No audit files found*'
	}

	It 'ignores directories, nested files, malformed names and other extensions' {
		$directory = Join-Path $script:folder 'folder_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640003.sqlaudit'
		$null = New-Item -Path $directory -ItemType Directory
		$null = New-Item -Path (Join-Path $directory 'nested_715e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640004.sqlaudit') -ItemType File
		foreach ($name in @(
			'malformed.sqlaudit'
			'audit_not-a-guid_0_123.sqlaudit'
			'audit_615e3b8a-9980-4739-89dd-b8ca9d93c36e_x_123.sqlaudit'
			'audit_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_invalid.sqlaudit'
			'audit_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_123.txt'
		)) {
			$null = New-Item -Path (Join-Path $script:folder $name) -ItemType File
		}
		$logFile = Join-Path $TestDrive 'no-matches.log'

		Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $script:folder -LogFile $logFile

		$messages = @(Get-Content -LiteralPath $logFile)
		$messages | Should -HaveCount 1
		$messages[0] | Should -BeLike '*No audit files found*'
	}

	It 'discovers three files across two audits without requiring credentials' {
		foreach ($name in @(
			'audit with spaces_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640003.sqlaudit'
			'audit_with_underscores_615E3B8A-9980-4739-89DD-B8CA9D93C36E_1_134289496418640004.sqlaudit'
			'other_audit_715e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640005.sqlaudit'
		)) {
			$null = New-Item -Path (Join-Path $script:folder $name) -ItemType File
		}
		$logFile = Join-Path $TestDrive 'discovered.log'
		# Stop at the SQL boundary without requiring a database or network access.
		{
			Invoke-Fast1Audit -ConnStr 'AuditTestInvalidKeyword=value' -Folder $script:folder -LogFile $logFile
		} | Should -Throw '*Keyword not supported*'

		$messages = Get-Content -LiteralPath $logFile
		$messages | Should -HaveCount 2
		$messages[0] | Should -BeLike '*3 audit file(s) found*'
		$messages[1] | Should -BeLike '*2 unique audit GUID(s) found*'
	}

	It 'preserves full file paths and parses GUIDs in a literal folder path' {
		$name = 'audit with_spaces_615E3B8A-9980-4739-89DD-B8CA9D93C36E_0_134289496418640003.sqlaudit'
		$filePath = Join-Path $script:folder $name
		$null = New-Item -Path $filePath -ItemType File

		$result = @(InModuleScope 'Fast1data.SqlServer' -Parameters @{ Folder = $script:folder } {
			Get-SqlAuditFile -Folder $Folder
		})

		$result | Should -HaveCount 1
		$result[0].FileName | Should -BeExactly $filePath
		$result[0].AuditGuid | Should -BeOfType ([guid])
		$result[0].AuditGuid | Should -Be ([guid]'615e3b8a-9980-4739-89dd-b8ca9d93c36e')
	}

	It 'reports a missing folder before attempting an import or logging discovery results' {
		$missingFolder = Join-Path $script:folder 'missing'
		$logFile = Join-Path $TestDrive 'missing-folder.log'
		$caught = $null
		$messages = @(
			try {
				Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $missingFolder `
					-LogFile $logFile -Verbose 4>&1
			}
			catch {
				$caught = $_
			}
		)

		$messages | Should -BeNullOrEmpty
		$caught | Should -Not -BeNullOrEmpty
		$caught.FullyQualifiedErrorId | Should -BeLike 'PathNotFound,*'
		Test-Path -LiteralPath $logFile | Should -BeFalse
	}
}
