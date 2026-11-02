<#
.SYNOPSIS
Disposes SQL resources and records cleanup failures without replacing a primary error.

.DESCRIPTION
Attempts Dispose on every non-null resource in dictionary enumeration order, even
when an earlier disposal fails. Use an ordered dictionary when release order matters.
Cleanup failures are attached to PrimaryError through Add-GenericSqlCleanupFailure.
When PrimaryError is absent, the first disposal error is thrown after all resources
have been attempted, with cleanup details attached to that error.

Initialize resources and the operation error to null before entering try. In catch,
save $_ as the operation error and rethrow it; call this helper in finally. Release
readers before commands and commands before connections. Include only resources
owned by the caller; leave borrowed connections for their owner to release.

.PARAMETER Resources
Maps resource role names, such as Reader or Command, to objects with a Dispose
method. Null values are skipped. Role names are included in cleanup details.

.PARAMETER PrimaryError
Specifies an existing operation error to preserve and annotate. When supplied,
disposal failures are recorded without throwing a replacement error.

.PARAMETER Context
Specifies additional cleanup metadata, such as GroupName, SourceTable or
ProcessStateId. Do not include connection strings, SQL text or other sensitive data.
Each disposal failure also receives Action and ResourceRole fields.

.PARAMETER FailureKey
Specifies the Exception.Data key under which cleanup details are stored.
Defaults to Fast1Sql.CleanupFailures. The shared retrieval helper recognizes this
key and Fast1Archiving.CleanupFailures.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
None. This function annotates errors and may throw the first disposal error.

.EXAMPLE
Close-GenericSqlResource -Resources ([ordered]@{ Reader = $reader; Command = $command }) -PrimaryError $operationError

Releases the reader before the command and records disposal failures on an
existing operation error. If that error is null, the first disposal failure is thrown.

.LINK
Add-GenericSqlCleanupFailure
#>
function Close-GenericSqlResource {
	[CmdletBinding()]
	param (
		[System.Collections.IDictionary]$Resources,
		[System.Management.Automation.ErrorRecord]$PrimaryError,
		[hashtable]$Context = @{},
		[string]$FailureKey = 'Fast1Sql.CleanupFailures'
	)

	$failure = $PrimaryError
	foreach ($role in $Resources.Keys) {
		if ($null -eq $Resources[$role]) {
			continue
		}
		try {
			$Resources[$role].Dispose()
		}
		catch {
			$cleanupError = $_
			if ($null -eq $failure) {
				$failure = $cleanupError
			}
			Add-GenericSqlCleanupFailure -PrimaryError $failure -CleanupError $cleanupError `
				-Context ($Context + @{ Action = 'Dispose'; ResourceRole = $role }) -FailureKey $FailureKey
		}
	}
	if ($null -eq $PrimaryError -and $null -ne $failure) {
		$PSCmdlet.ThrowTerminatingError($failure)
	}
}

<#
.SYNOPSIS
Attaches cleanup failure details to an existing error.

.DESCRIPTION
Collects cleanup entries already attached to the primary and cleanup errors,
including their inner exceptions. Enriches existing entries with missing GroupName,
SourceTable and ProcessStateId values from Context, then appends the new failure.
Stores the combined entries in PrimaryError.Exception.Data under FailureKey.
The new entry contains the supplied context, the base exception type and a fixed
message. Provider exception messages are omitted because they may contain
connection strings or SQL text. This function does not throw the supplied errors.

.PARAMETER PrimaryError
Specifies the error that receives the combined cleanup details.

.PARAMETER CleanupError
Specifies the cleanup error whose base exception type and existing cleanup details
are added to PrimaryError.

.PARAMETER Context
Specifies a hashtable of cleanup metadata. Use an empty hashtable when no context
is available. Include only metadata suitable for reporting, such as Action,
ResourceRole, GroupName, SourceTable or ProcessStateId.

.PARAMETER FailureKey
Specifies the Exception.Data key under which combined entries are stored.
Defaults to Fast1Sql.CleanupFailures. Get-GenericSqlCleanupFailure recognizes this
key and Fast1Archiving.CleanupFailures.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
None. This function updates the supplied primary error and existing cleanup entries.

.EXAMPLE
Add-GenericSqlCleanupFailure -PrimaryError $operationError -CleanupError $cleanupError -Context @{ Action = 'Dispose'; ResourceRole = 'Command' }

Records a command disposal failure on the original operation error.

.LINK
Get-GenericSqlCleanupFailure
#>
function Add-GenericSqlCleanupFailure {
	[CmdletBinding()]
	param (
		[System.Management.Automation.ErrorRecord]$PrimaryError,
		[System.Management.Automation.ErrorRecord]$CleanupError,
		[hashtable]$Context,
		[string]$FailureKey = 'Fast1Sql.CleanupFailures'
	)

	$entries = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in @(Get-GenericSqlCleanupFailure -ErrorRecord @($PrimaryError, $CleanupError))) {
		foreach ($identity in @('GroupName', 'SourceTable', 'ProcessStateId')) {
			if ($Context.ContainsKey($identity) -and -not $entry.PSObject.Properties[$identity]) {
				$entry | Add-Member -NotePropertyName $identity -NotePropertyValue $Context[$identity]
			}
		}
		$entries.Add($entry)
	}
	$entries.Add([PSCustomObject]($Context + @{
		ErrorType = $CleanupError.Exception.GetBaseException().GetType().FullName
		Message = 'The identified cleanup action failed.'
	}))
	$PrimaryError.Exception.Data[$FailureKey] = $entries
}

<#
.SYNOPSIS
Retrieves cleanup failure details from errors and their inner exceptions.

.DESCRIPTION
Walks each supplied error's exception chain from the innermost exception outward.
Collects entries stored under Fast1Sql.CleanupFailures and
Fast1Archiving.CleanupFailures in Exception.Data. Skips null entries and repeated
references to the same entry; separate entries with identical fields remain distinct.

.PARAMETER ErrorRecord
Specifies the errors whose exception chains are inspected, in processing order.

.INPUTS
None. Supply error records through the ErrorRecord parameter.

.OUTPUTS
System.Management.Automation.PSCustomObject. Returns recorded cleanup entries
containing their original metadata. Returns no objects when no entries are found.

.EXAMPLE
Get-GenericSqlCleanupFailure -ErrorRecord $operationError

Returns cleanup details attached to an operation error or its inner exceptions.

.LINK
Add-GenericSqlCleanupFailure
#>
function Get-GenericSqlCleanupFailure {
	param ([System.Management.Automation.ErrorRecord[]]$ErrorRecord)
	$entries = [System.Collections.Generic.List[object]]::new()
	foreach ($record in $ErrorRecord) {
		$exceptions = [System.Collections.Generic.List[System.Exception]]::new()
		$exception = $record.Exception
		while ($null -ne $exception) {
			$exceptions.Add($exception)
			$exception = $exception.InnerException
		}
		$exceptions.Reverse()
		foreach ($exception in $exceptions) {
			foreach ($key in @('Fast1Sql.CleanupFailures', 'Fast1Archiving.CleanupFailures')) {
				foreach ($entry in @($exception.Data[$key])) {
					if ($null -ne $entry -and -not $entries.Contains($entry)) {
						$entries.Add($entry)
					}
				}
			}
		}
	}
	$entries.ToArray()
}
