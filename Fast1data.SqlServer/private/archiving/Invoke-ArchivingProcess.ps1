using module ./ArchivingModel.psm1

<#
.SYNOPSIS
Executes archiving and purging for a configured table group.

.DESCRIPTION
Creates a fresh TableGroup instance and delegates the execution request to its
Execute method. The instance owns initialization, configured archive and purge
operations, checkpoints, foreign-key restoration and resource cleanup.

Operation errors propagate to the caller with the original error preserved.
Secondary cleanup details are attached to the exception under
Exception.Data['Fast1Archiving.CleanupFailures']. Cleanup failures also terminate
the request when no earlier operation error exists.

Data changes and checkpoints commit independently. Retry incomplete work through
a new invocation for the same group, retaining its state and working tables,
keeping configuration stable and preventing concurrent execution of that group.

.PARAMETER ConnStr
Specifies the Microsoft.Data.SqlClient connection string for the archiving
configuration database.

.PARAMETER GroupName
Specifies the configured table-group name to archive or purge.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
None. This function delegates execution without returning a result object.

.EXAMPLE
Invoke-ArchivingProcess -ConnStr $connectionString -GroupName 'History'

Executes the configured History table group. Progress messages use the verbose
stream and warnings use the warning stream.

.LINK
Invoke-Fast1Archiving
#>
function Invoke-ArchivingProcess {
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$GroupName
	)

	$group = [TableGroup]::new($ConnStr, $GroupName)
	$group.Execute()
}
