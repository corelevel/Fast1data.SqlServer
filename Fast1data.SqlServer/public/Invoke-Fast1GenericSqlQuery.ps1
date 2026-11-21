<#
.SYNOPSIS
Executes a parameterized SQL command.

.DESCRIPTION
Creates a Microsoft.Data.SqlClient command on an existing connection, adds
parameters created by New-Fast1GenericSqlParam, and executes the command as either
a silent non-query or scalar operation. The function disposes its command on
success or failure. The caller owns the already-open connection and must dispose
it afterward; this command never opens, closes, or disposes that connection.
Command timeout retains the provider default. SQL text and procedure names are
executable administrator inputs.

.PARAMETER SqlConn
Specifies an open Microsoft.Data.SqlClient connection.

.PARAMETER Query
Specifies the SQL text or stored-procedure name to execute.

.PARAMETER CommandType
Specifies whether Query contains SQL text or a stored-procedure name.

.PARAMETER Parameters
Specifies typed descriptors keyed by parameter name without @. Create them with
New-Fast1GenericSqlParam. Null values bind as DBNull.Value; non-null values retain
native types, including byte arrays. Only positive Size/Precision/Scale values
are forwarded; zero retains provider defaults, including decimal scale inference.

.PARAMETER Scalar
Returns the first column of the first result row instead of executing the
command as a non-query.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
System.Object. With Scalar, the provider's first-column/first-row result, retaining
its existing null/DBNull behavior. Without Scalar, no output (including row counts).

.EXAMPLE
$parameters = @{ Id = New-Fast1GenericSqlParam -Type BigInt -Value 42 }
Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'SELECT @Id' -Parameters $parameters -Scalar

Retrieves a scalar on an already-open caller-owned connection.

.EXAMPLE
$parameters = @{ Name = New-Fast1GenericSqlParam -Type NVarChar -Size 100 }
Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'UPDATE dbo.Example SET Name = @Name' -Parameters $parameters

Executes a silent non-query using typed SQL NULL. The caller disposes the connection.
#>
function Invoke-Fast1GenericSqlQuery {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[Microsoft.Data.SqlClient.SqlConnection]$SqlConn,

		[Parameter(Mandatory)]
		[string]$Query,

		[System.Data.CommandType]$CommandType = [System.Data.CommandType]::Text,
		[hashtable]$Parameters,
		[switch]$Scalar
	)

	$sqlCmd = $null
	$operationError = $null
	try {
		$sqlCmd = Get-GenericSqlCommand -Query $Query -SqlConn $SqlConn
		$sqlCmd.CommandType = $CommandType

		Add-GenericSqlParameter -SqlCmd $sqlCmd -Parameters $Parameters

		if ($Scalar) {
			return $sqlCmd.ExecuteScalar()
		}

		[void]$sqlCmd.ExecuteNonQuery()
	}
	catch {
		$operationError = $_
		throw
	}
	finally {
		Close-GenericSqlResource -Resources ([ordered]@{ Command = $sqlCmd }) -PrimaryError $operationError
	}
}
