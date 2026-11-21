# Offline interception uses real provider objects, but does not prove SQL/session behavior.
function Get-MigrationTestCommand {
	[CmdletBinding()]
	param ([Microsoft.Data.SqlClient.SqlConnection]$Connection)
	if ($null -eq $Connection) {
		$Connection = [Microsoft.Data.SqlClient.SqlConnection]::new()
	}
	$connection = $Connection
	$connection | Add-Member -NotePropertyName State -NotePropertyValue ([System.Data.ConnectionState]::Open) -Force
	$connection | Add-Member -NotePropertyName Database -NotePropertyValue 'current_target' -Force
	$connection | Add-Member -NotePropertyName TestEvents -NotePropertyValue ([System.Collections.Generic.List[string]]::new())
	$command = [Microsoft.Data.SqlClient.SqlCommand]::new('', $connection)
	$command.CommandTimeout = 73
	$command | Add-Member -NotePropertyName Observations -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
	$command | Add-Member -NotePropertyName FailAt -NotePropertyValue 0
	$command | Add-Member -NotePropertyName TransactionCount -NotePropertyValue 0
	$command | Add-Member -NotePropertyName FailCheck -NotePropertyValue $false
	$command | Add-Member -NotePropertyName Checks -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
	$command | Add-Member -MemberType ScriptMethod -Name ExecuteScalar -Force -Value {
		$this.Checks.Add([pscustomobject]@{
			Text = $this.CommandText
			Connection = $this.Connection
			Timeout = $this.CommandTimeout
			ParameterCount = $this.Parameters.Count
		})
		if ($this.FailCheck) {
			throw 'controlled completion check failure with private details'
		}
		return $this.TransactionCount
	}
	$command | Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Force -Value {
		$this.Observations.Add([pscustomobject]@{
			Text = $this.CommandText
			Connection = $this.Connection
			Ambient = [System.Transactions.Transaction]::Current
			Timeout = $this.CommandTimeout
			Parameters = @($this.Parameters | ForEach-Object {
				[pscustomobject]@{ Name = $_.ParameterName; Type = $_.SqlDbType; Size = $_.Size; Value = $_.Value }
			})
		})
		if ($this.FailAt -eq $this.Observations.Count) {
			throw [System.InvalidOperationException]::new('controlled provider failure with private SQL details')
		}
		return 1
	}
	return $command
}

# Owned execution resources with deterministic I/O and cleanup observations.
function Get-MigrationTestExecution {
	param ([string]$ConnStr = 'Server=unused;Database=configured_target')
	$events = [System.Collections.Generic.List[string]]::new()
	$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($ConnStr)
	$command = Get-MigrationTestCommand -Connection $connection
	$fixture = [pscustomobject]@{
		Connection = $connection
		Command = $command
		Events = $events
		FailOpen = $false
		FailCommandCleanup = $false
		FailConnectionCleanup = $false
	}
	$connection | Add-Member -NotePropertyName Fixture -NotePropertyValue $fixture
	$command | Add-Member -NotePropertyName Fixture -NotePropertyValue $fixture
	$connection | Add-Member -MemberType ScriptMethod -Name Open -Force -Value {
		$this.Fixture.Events.Add('open')
		if ($null -ne [System.Transactions.Transaction]::Current) {
			throw 'Script connection must open under ambient suppression.'
		}
		if ($this.Fixture.FailOpen) {
			throw 'private open details'
		}
	}
	$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
		$this.Fixture.Events.Add('command-dispose')
		$this.psbase.Dispose()
		if ($null -ne [System.Transactions.Transaction]::Current) {
			throw 'Command disposal must remain under ambient suppression.'
		}
		if ($this.Fixture.FailCommandCleanup) {
			throw 'private command disposal details'
		}
	}
	$connection | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
		$this.Fixture.Events.Add('connection-dispose')
		$this.psbase.Dispose()
		if ($null -ne [System.Transactions.Transaction]::Current) {
			throw 'Connection disposal must remain under ambient suppression.'
		}
		if ($this.Fixture.FailConnectionCleanup) {
			throw 'private connection disposal details'
		}
	}
	$fixture
}
