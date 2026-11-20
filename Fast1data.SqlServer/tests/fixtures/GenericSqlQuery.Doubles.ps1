# Test-only resources. Load the selected distribution through Import-SharedHelperDependency.ps1 first.
function Get-GenericSqlTestExecution {
	param ([object[]]$Results = @(@{ Names = @('Id'); Rows = @(@{ Values = @(1) }, @{ Values = @(2) }) }))
	$state = [pscustomobject]@{
		Events = [System.Collections.Generic.List[string]]::new()
		Results = $Results
		ResultIndex = 0
		RowIndex = -1
		ReadCount = 0
		FailAt = ''
		FailRead = 0
		FailDisposal = @()
		ScalarValue = 42
	}
	$reader = [pscustomobject]@{ State = $state }
	$reader | Add-Member -MemberType ScriptProperty -Name FieldCount -Value {
		$this.State.Events.Add('FieldCount')
		if ($this.State.FailAt -eq 'FieldCount') {
			throw 'controlled FieldCount failure'
		}
		$this.State.Results[$this.State.ResultIndex].Names.Count
	}
	$reader | Add-Member -MemberType ScriptMethod -Name NextResult -Value {
		$this.State.Events.Add('NextResult')
		if ($this.State.FailAt -eq 'NextResult') {
			throw 'controlled NextResult failure'
		}
		$this.State.ResultIndex++
		$this.State.RowIndex = -1
		$this.State.ResultIndex -lt $this.State.Results.Count
	}
	$reader | Add-Member -MemberType ScriptMethod -Name GetName -Value {
		param ($Ordinal)
		$this.State.Events.Add("GetName:$Ordinal")
		if ($this.State.FailAt -eq 'GetName') {
			throw 'controlled GetName failure'
		}
		$this.State.Results[$this.State.ResultIndex].Names[$Ordinal]
	}
	$reader | Add-Member -MemberType ScriptMethod -Name Read -Value {
		$this.State.ReadCount++
		$this.State.Events.Add("Read:$($this.State.ReadCount)")
		if ($this.State.FailAt -eq 'Read' -or $this.State.FailRead -eq $this.State.ReadCount) {
			throw 'controlled Read failure'
		}
		$this.State.RowIndex++
		$this.State.RowIndex -lt $this.State.Results[$this.State.ResultIndex].Rows.Count
	}
	$reader | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
		param ($Ordinal)
		$this.State.Events.Add("GetValue:$Ordinal")
		if ($this.State.FailAt -eq 'GetValue') {
			throw 'controlled GetValue failure'
		}
		return ,$this.State.Results[$this.State.ResultIndex].Rows[$this.State.RowIndex].Values[$Ordinal]
	}
	$reader | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
		$this.State.Events.Add('Reader.Dispose')
		if ('Reader' -in $this.State.FailDisposal) {
			throw 'controlled Reader disposal failure'
		}
	}
	$connection = [Microsoft.Data.SqlClient.SqlConnection]::new()
	$connection | Add-Member -NotePropertyName TestState -NotePropertyValue $state
	foreach ($method in @('Open', 'Close', 'Dispose')) {
		$connection | Add-Member -MemberType ScriptMethod -Name $method -Force -Value ([scriptblock]::Create("
`$this.TestState.Events.Add('Connection.$method')
if ('$method' -in `$this.TestState.FailDisposal -or `$this.TestState.FailAt -eq '$method') {
`tthrow 'controlled Connection $method failure'
}
"))
	}
	$command = [Microsoft.Data.SqlClient.SqlCommand]::new('', $connection)
	$command | Add-Member -NotePropertyName TestState -NotePropertyValue $state
	$command | Add-Member -NotePropertyName TestReader -NotePropertyValue $reader
	$command | Add-Member -MemberType ScriptMethod -Name ExecuteReader -Force -Value {
		$this.TestState.Events.Add('ExecuteReader')
		if ($this.TestState.FailAt -eq 'ExecuteReader') {
			throw 'controlled ExecuteReader failure'
		}
		$this.TestReader
	}
	$command | Add-Member -MemberType ScriptMethod -Name ExecuteScalar -Force -Value {
		$this.TestState.Events.Add('ExecuteScalar')
		if ($this.TestState.FailAt -eq 'ExecuteScalar') {
			throw 'controlled ExecuteScalar failure'
		}
		return ,$this.TestState.ScalarValue
	}
	$command | Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Force -Value {
		$this.TestState.Events.Add('ExecuteNonQuery')
		if ($this.TestState.FailAt -eq 'ExecuteNonQuery') {
			throw 'controlled ExecuteNonQuery failure'
		}
		17
	}
	$command | Add-Member -MemberType ScriptMethod -Name Dispose -Force -Value {
		$this.TestState.Events.Add('Command.Dispose')
		if ('Command' -in $this.TestState.FailDisposal) {
			throw 'controlled Command disposal failure'
		}
	}
	[pscustomobject]@{ State = $state; Reader = $reader; Command = $command; Connection = $connection }
}
