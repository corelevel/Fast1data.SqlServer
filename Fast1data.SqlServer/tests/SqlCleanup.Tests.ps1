BeforeAll {
	Import-Module (Join-Path $PSScriptRoot '../Fast1data.SqlServer.psd1') -Force
	InModuleScope Fast1data.SqlServer {
		$script:cleanupImplementation = (Get-Command Close-GenericSqlResource).ScriptBlock
	}
}

Describe 'Shared SQL resource cleanup' {
	It 'attempts every resource in order and throws the first cleanup failure after releasing the rest' {
		InModuleScope Fast1data.SqlServer {
			$events = [System.Collections.Generic.List[string]]::new()
			$resources = [ordered]@{ Unallocated = $null }
			foreach ($role in @('Reader', 'Command', 'Connection')) {
				$resource = [PSCustomObject]@{ Role = $role; Events = $events }
				$resource | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
					$this.Events.Add($this.Role)
					if ($this.Role -ne 'Connection') {
						throw "$($this.Role) cleanup failed"
					}
				}
				$resources[$role] = $resource
			}
			$caught = $null
			try {
				Close-GenericSqlResource -Resources $resources
			}
			catch {
				$caught = $_
			}

			$events -join ',' | Should -Be 'Reader,Command,Connection'
			$caught.Exception.Message | Should -BeLike '*Reader cleanup failed*'
			$failures = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$failures.ResourceRole -join ',' | Should -Be 'Reader,Command'
			$failures.Message | Should -Not -Contain 'Reader cleanup failed'
		}
	}

	It 'releases successful resources without emitting output' {
		InModuleScope Fast1data.SqlServer {
			$resource = [PSCustomObject]@{ Released = $false }
			$resource | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
				$this.Released = $true
			}

			$result = @(Close-GenericSqlResource -Resources ([ordered]@{ Reader = $null; Command = $resource }))

			$result | Should -BeNullOrEmpty
			$resource.Released | Should -BeTrue
		}
	}
}

Describe 'Audit and migration cleanup on operation failure' {
	BeforeEach {
		InModuleScope Fast1data.SqlServer {
			$script:cleanupState = [PSCustomObject]@{
				PrimaryError = $null
				Roles = @()
				Released = [System.Collections.Generic.List[string]]::new()
			}
			Mock Get-SqlAuditFile {
				[PSCustomObject]@{ AuditGuid = [guid]::Empty }
			}
			Mock Close-GenericSqlResource {
				$script:cleanupState.PrimaryError = $PrimaryError
				$script:cleanupState.Roles = @($Resources.Keys)
				foreach ($role in $Resources.Keys) {
					if ($null -eq $Resources[$role]) {
						continue
					}
					$Resources[$role] | Add-Member -NotePropertyName CleanupState -NotePropertyValue $script:cleanupState
					$Resources[$role] | Add-Member -NotePropertyName CleanupRole -NotePropertyValue $role
					$Resources[$role] | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
						$this.CleanupState.Released.Add($this.CleanupRole)
						$this.psbase.Dispose()
						throw 'Controlled cleanup failure'
					}
				}
				& $script:cleanupImplementation -Resources $Resources -PrimaryError $PrimaryError
			}
		}
	}

	It '<CommandName> preserves its operation error when cleanup also fails' -ForEach @(
		@{ CommandName = 'Get-Executed'; Roles = 'Reader,Command,Connection'; Released = 'Connection' }
		@{ CommandName = 'Set-Executed'; Roles = 'Connection'; Released = 'Connection' }
		@{ CommandName = 'Get-ImportState'; Roles = 'Reader,Command'; Released = 'Command' }
		@{ CommandName = 'Import-SqlAuditFile'; Roles = 'Reader,Command'; Released = 'Command' }
		@{ CommandName = 'Invoke-Fast1Audit'; Roles = 'Connection'; Released = 'Connection' }
	) {
		InModuleScope Fast1data.SqlServer -Parameters @{ CommandName = $CommandName; Roles = $Roles; Released = $Released } {
			$connection = [Microsoft.Data.SqlClient.SqlConnection]::new()
			$caught = $null
			try {
				switch ($CommandName) {
					'Get-Executed' {
						Get-Executed -ConnStr 'InvalidKeyword=value' -Phase 'test'
					}
					'Set-Executed' {
						Set-Executed -ConnStr 'InvalidKeyword=value' -ScriptName 'test.sql' -Phase 'test' -Checksum 'hash' -ForceScript $false
					}
					'Get-ImportState' {
						Get-ImportState -SqlConn $connection -AuditGuids @([guid]::Empty)
					}
					'Import-SqlAuditFile' {
						Import-SqlAuditFile -SqlConn $connection -Folder 'unused' -AuditGuid ([guid]::Empty)
					}
					'Invoke-Fast1Audit' {
						Invoke-Fast1Audit -ConnStr 'InvalidKeyword=value' -Folder 'unused'
					}
				}
			}
			catch {
				$caught = $_
			}
			finally {
				$connection.Dispose()
			}

			$caught | Should -Not -BeNullOrEmpty
			[object]::ReferenceEquals($caught.Exception, $script:cleanupState.PrimaryError.Exception) | Should -BeTrue
			$script:cleanupState.Roles -join ',' | Should -Be $Roles
			$script:cleanupState.Released -join ',' | Should -Be $Released
			$failures = @(Get-GenericSqlCleanupFailure -ErrorRecord $caught)
			$failures.ResourceRole -join ',' | Should -Be $Released
			Should -Invoke Close-GenericSqlResource -Times 1 -Exactly
		}
	}
}
