[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText',
    '',
    Justification = 'Dummy credentials used only in Pester tests.'
)]
param()

BeforeAll {
	Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fast1data.SqlServer.psd1') -Force
}

Describe 'Audit import from Linux' -Tag 'Linux' -Skip:(-not $IsLinux) {
	BeforeAll {
		$script:originalPath = $env:PATH
		$script:hadPasswd = Test-Path Env:PASSWD
		$script:originalPasswd = $env:PASSWD
		$script:binPath = Join-Path $TestDrive 'bin'
		$null = New-Item -Path $script:binPath -ItemType Directory
		$script:smbPath = Join-Path $script:binPath 'smbclient'
		$script:credential = [pscredential]::new('DOMAIN\audit reader',
			(ConvertTo-SecureString 'audit-test-password' -AsPlainText -Force))
		$script:folder = '\\audit-server\audit share\nested folder'
	}

	BeforeEach {
		$env:PATH = "$script:binPath$([IO.Path]::PathSeparator)$script:originalPath"
		$env:PASSWD = 'prior-test-password'
		# A native process at the SMB boundary; production discovery stays intact.
		@'
#!/bin/sh
exit 0
'@ | Set-Content -LiteralPath $script:smbPath -NoNewline
		& /bin/chmod +x $script:smbPath
	}

	AfterEach {
		$env:PATH = $script:originalPath
		if ($script:hadPasswd) {
			$env:PASSWD = $script:originalPasswd
		}
		else {
			Remove-Item Env:PASSWD -ErrorAction SilentlyContinue
		}
	}

	It 'returns without connecting to SQL when the share is empty' {
		$messages = @(Invoke-Fast1Audit -ConnStr 'invalid connection string' `
			-Folder $script:folder -Credential $script:credential -Verbose 4>&1)

		$messages | Should -HaveCount 1
		$messages[0].Message | Should -BeLike '*No audit files found*'
		$env:PASSWD | Should -BeExactly 'prior-test-password'
	}

	It 'requires SMB credentials before attempting an import' -ForEach @(
		@{ CredentialKind = 'missing' }
		@{ CredentialKind = 'empty' }
	) {
		$arguments = @{}
		if ($CredentialKind -eq 'empty') {
			$arguments.Credential = [pscredential]::Empty
		}
		{
			Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $script:folder @arguments
		} | Should -Throw '*Credential is required for Linux*'
		$env:PASSWD | Should -BeExactly 'prior-test-password'
	}

	It 'rejects unsupported folder <Folder>' -ForEach @(
		@{ Folder = '/var/opt/mssql/audit' }
		@{ Folder = 'relative/audit' }
		@{ Folder = '\\server' }
	) {
		{
			Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $Folder -Credential $script:credential
		} | Should -Throw '*Specify a UNC server/share folder*'
		$env:PASSWD | Should -BeExactly 'prior-test-password'
	}

	It 'reports a missing smbclient before attempting an import' {
		$emptyPath = Join-Path $TestDrive 'empty-bin'
		$null = New-Item -Path $emptyPath -ItemType Directory
		$env:PATH = $emptyPath
		{
			Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $script:folder -Credential $script:credential
		} | Should -Throw '*smbclient is not installed or not available in PATH*'
	}

	It 'ignores directories, malformed names and listing metadata' {
		@'
#!/bin/sh
printf '%s\n' \
  '  .                                   D        0  Fri Oct 30 12:00:00 2026' \
  '  folder_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640003.sqlaudit D 0 Fri Oct 30 12:00:00 2026' \
  '  malformed.sqlaudit                   A      100  Fri Oct 30 12:00:00 2026' \
  '  audit_not-a-guid_0_123.sqlaudit       A      100  Fri Oct 30 12:00:00 2026' \
  '  audit_615e3b8a-9980-4739-89dd-b8ca9d93c36e_x_123.sqlaudit A 100 Fri Oct 30 12:00:00 2026' \
  '                1024 blocks of size 4096. 512 blocks available'
'@ | Set-Content -LiteralPath $script:smbPath -NoNewline
		$logFile = Join-Path $TestDrive 'no-matches.log'
		Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $script:folder `
			-Credential $script:credential -LogFile $logFile

		Get-Content -LiteralPath $logFile | Should -BeLike '*No audit files found*'
	}

	It 'discovers three files across two audits and passes SMB credentials without password arguments' {
		@'
#!/bin/sh
# Check the external process contract, including spaces in arguments.
if [ "$#" -ne 7 ] || [ "$1" != '//audit-server/audit share' ] ||
   [ "$2" != '-U' ] || [ "$3" != 'DOMAIN\audit reader' ] ||
   [ "$4" != '-c' ] || [ "$5" != 'ls' ] ||
   [ "$6" != '-D' ] || [ "$7" != 'nested folder' ] ||
   [ "$PASSWD" != 'audit-test-password' ]; then
  echo 'Unexpected SMB invocation' >&2
  exit 23
fi
printf '%s\n' \
  '  audit with spaces_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640003.sqlaudit A 100 Fri Oct 30 12:00:00 2026' \
  '  audit_with_underscores_615E3B8A-9980-4739-89DD-B8CA9D93C36E_1_134289496418640004.sqlaudit A 100 Fri Oct 30 12:00:00 2026' \
  '  other_audit_715e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640005.sqlaudit A 100 Fri Oct 30 12:00:00 2026'
'@ | Set-Content -LiteralPath $script:smbPath -NoNewline
		$logFile = Join-Path $TestDrive 'discovered.log'
		# Stop at the SQL boundary without requiring a database or network access.
		{
			Invoke-Fast1Audit -ConnStr 'AuditTestInvalidKeyword=value' -Folder $script:folder `
				-Credential $script:credential -LogFile $logFile
		} | Should -Throw '*Keyword not supported*'

		$messages = Get-Content -LiteralPath $logFile
		$messages | Should -HaveCount 2
		$messages[0] | Should -BeLike '*3 audit file(s) found*'
		$messages[1] | Should -BeLike '*2 unique audit GUID(s) found*'
		$env:PASSWD | Should -BeExactly 'prior-test-password'
	}

	It 'restores PASSWD (<PriorState>) after <Outcome>, with native errors <NativeErrors>' -ForEach @(
		foreach ($priorState in @('absent', 'present', 'empty')) {
			foreach ($outcome in @('empty listing', 'failed listing')) {
				foreach ($nativeErrors in @($false, $true)) {
					@{ PriorState = $priorState; Outcome = $outcome; NativeErrors = $nativeErrors }
				}
			}
		}
	) {
		if ($PriorState -eq 'empty' -and $PSVersionTable.PSVersion -lt [version]'7.5') {
			Set-ItResult -Skipped -Because 'PowerShell before 7.5 cannot preserve empty environment variables.'
			return
		}
		if ($PriorState -eq 'absent') {
			Remove-Item Env:PASSWD
		}
		elseif ($PriorState -eq 'empty') {
			$env:PASSWD = ''
		}
		$PSNativeCommandUseErrorActionPreference = $NativeErrors
		if ($Outcome -eq 'failed listing') {
			@'
#!/bin/sh
printf '%s\n' '  audit_615e3b8a-9980-4739-89dd-b8ca9d93c36e_0_134289496418640003.sqlaudit A 100 Fri Oct 30 12:00:00 2026'
echo 'Access denied: audit-test-password prior-test-password' >&2
exit 7
'@ | Set-Content -LiteralPath $script:smbPath -NoNewline
		}
		$caught = $null
		$messages = @(
			try {
				Invoke-Fast1Audit -ConnStr 'invalid connection string' -Folder $script:folder `
					-Credential $script:credential -Verbose 4>&1
			}
			catch {
				$caught = $_
			}
		)
		if ($Outcome -eq 'failed listing') {
			$messages | Should -BeNullOrEmpty
			$caught.FullyQualifiedErrorId | Should -BeLike 'SqlAuditSmbListingFailed,*'
			$caught.Exception.Message | Should -BeLike '*exit code 7*Access denied*'
			$caught.Exception.Message | Should -Not -BeLike '*audit-test-password*'
			if ($PriorState -eq 'present') {
				$caught.Exception.Message | Should -Not -BeLike '*prior-test-password*'
			}
		}
		else {
			$caught | Should -BeNullOrEmpty
			$messages | Should -HaveCount 1
			$messages[0].Message | Should -BeLike '*No audit files found*'
		}
		$PSNativeCommandUseErrorActionPreference | Should -Be $NativeErrors
		(Test-Path Env:PASSWD) | Should -Be ($PriorState -ne 'absent')
		if ($PriorState -eq 'present') {
			$env:PASSWD | Should -BeExactly 'prior-test-password'
		}
		elseif ($PriorState -eq 'empty') {
			$env:PASSWD | Should -BeExactly ''
		}
	}
}
