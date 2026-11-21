<#
.SYNOPSIS
Streams objects from the first tabular SQL result on an existing connection.

.DESCRIPTION
Emits one fresh ordered object per row, retaining SQL column names, order and
native values (including byte arrays); only DBNull becomes PowerShell null.
Leading results without columns are skipped. The first result with columns is
selected even when empty; later results are never emitted. Blank or ordinal
case-insensitive duplicate names fail before reading, including for empty results.
Use distinct SQL aliases to name each column.

Rows are emitted incrementally before the next read. A later failure terminates
execution but previously delivered rows remain available. Entire individual
values can be materialized; there is no atomic-output guarantee. Downstream
termination stops application reads and releases the reader and command. The
caller owns the already-open connection and must dispose it afterward.

Reader disposal may wait for pending results and later SQL statements may execute.
This command does not cancel, roll back, or promise immediate cleanup. It retains
the provider's default timeout and executes administrator-supplied SQL text or
procedure names. Owned reader then command cleanup preserves primary errors and
records safe cleanup details under Fast1Sql.CleanupFailures.
When downstream stops the pipeline, PowerShell can suppress cleanup exceptions
after they are thrown; owned disposals are still attempted in the same order.

.PARAMETER SqlConn
Borrowed, already-open Microsoft.Data.SqlClient connection. Never opened, closed,
or disposed by this command.

.PARAMETER Query
Mandatory SQL text or stored-procedure name; executable administrator input.

.PARAMETER CommandType
Text by default. Use StoredProcedure when Query names a stored procedure.

.PARAMETER Parameters
Optional typed descriptors created by New-Fast1GenericSqlParam, keyed without @.
Null binds to SQL NULL; other native values are preserved. Only positive metadata
is forwarded; zero leaves provider defaults, including decimal scale inference.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject. One independent ordered object per
row, or no output for an empty first tabular result or a command without columns.

.EXAMPLE
$parameters = @{ Id = New-Fast1GenericSqlParam -Type BigInt -Value 42 }
Invoke-Fast1GenericSqlQueryReader -SqlConn $connection -Query 'SELECT @Id AS Id' -Parameters $parameters | Export-Csv ./rows.csv -NoTypeInformation

Streams CSV rows using an already-open caller-owned connection.

.EXAMPLE
Invoke-Fast1GenericSqlQueryReader -SqlConn $connection -Query 'SELECT 1 AS Id WHERE 1 = 0; SELECT 2 AS Later;'

Emits nothing because the first tabular result is empty. Later SQL can still execute.
#>
function Invoke-Fast1GenericSqlQueryReader {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[Microsoft.Data.SqlClient.SqlConnection]$SqlConn,

		[Parameter(Mandatory)]
		[string]$Query,

		[System.Data.CommandType]$CommandType = [System.Data.CommandType]::Text,
		[hashtable]$Parameters
	)

	$sqlCmd = $null
	$sqlReader = $null
	$operationError = $null
	try {
		$sqlCmd = Get-GenericSqlCommand -Query $Query -SqlConn $SqlConn
		$sqlCmd.CommandType = $CommandType
		Add-GenericSqlParameter -SqlCmd $sqlCmd -Parameters $Parameters
		$sqlReader = $sqlCmd.ExecuteReader()

		while ($sqlReader.FieldCount -eq 0) {
			if (-not $sqlReader.NextResult()) {
				return
			}
		}

		$names = [System.Collections.Generic.List[string]]::new()
		$uniqueNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		for ($ordinal = 0; $ordinal -lt $sqlReader.FieldCount; $ordinal++) {
			$name = $sqlReader.GetName($ordinal)
			if ([string]::IsNullOrWhiteSpace($name) -or -not $uniqueNames.Add($name)) {
				throw 'Column names must be nonblank and unique; use distinct SQL aliases for every column.'
			}
			$names.Add($name)
		}

		while ($sqlReader.Read()) {
			$row = [ordered]@{}
			for ($ordinal = 0; $ordinal -lt $names.Count; $ordinal++) {
				$value = $sqlReader.GetValue($ordinal)
				if ($value -is [DBNull]) {
					$value = $null
				}
				$row[$names[$ordinal]] = $value
			}
			[pscustomobject]$row
		}
	}
	catch {
		$operationError = $_
		throw
	}
	finally {
		Close-GenericSqlResource -Resources ([ordered]@{ Reader = $sqlReader; Command = $sqlCmd }) -PrimaryError $operationError
	}
}
