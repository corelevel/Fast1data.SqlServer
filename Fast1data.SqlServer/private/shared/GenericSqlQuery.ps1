using module ./GenericSqlParam.psm1

. "$PSScriptRoot\GenericSqlCleanup.ps1"

<#
.SYNOPSIS
Creates a SQL command for an existing connection.

.DESCRIPTION
Constructs a Microsoft.Data.SqlClient.SqlCommand with the supplied query and
connection. The command is returned without opening the connection or executing
the query. The caller is responsible for disposing the command. This helper also
allows tests to substitute a controlled command for Invoke-GenericSqlQuery.

.PARAMETER Query
Specifies the command text. To execute a stored procedure, supply its name and
set the returned command's CommandType to StoredProcedure before execution.

.PARAMETER SqlConn
Specifies the Microsoft.Data.SqlClient connection associated with the command.
The connection must be open before the command is executed.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
Microsoft.Data.SqlClient.SqlCommand. Returns the newly created command.

.EXAMPLE
$command = Get-GenericSqlCommand -Query 'SELECT 1' -SqlConn $connection

Creates a command on the supplied connection without executing it.

.LINK
Invoke-GenericSqlQuery
#>
function Get-GenericSqlCommand {
	param ([string]$Query, [Microsoft.Data.SqlClient.SqlConnection]$SqlConn)
	[Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn)
}

<#
.SYNOPSIS
Executes a parameterized SQL command.

.DESCRIPTION
Creates a Microsoft.Data.SqlClient command on an existing connection, adds
parameters described by GenericSqlParam values, and executes the command as either
a non-query or scalar operation.

.PARAMETER SqlConn
Specifies an open Microsoft.Data.SqlClient connection.

.PARAMETER Query
Specifies the SQL text or stored-procedure name to execute.

.PARAMETER CommandType
Specifies whether Query contains SQL text or a stored-procedure name.

.PARAMETER Parameters
Specifies command parameters keyed by parameter name. Each value must be an
GenericSqlParam instance.

.PARAMETER Scalar
Returns the first column of the first result row instead of executing the
command as a non-query.
#>
function Invoke-GenericSqlQuery {
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

		if ($Parameters) {
			foreach ($name in $Parameters.Keys) {
				$param = $Parameters[$name]

				if ($param -isnot [GenericSqlParam]) {
					throw "Parameter '$name' must be of type GenericSqlParam"
				}

				if (-not $param.Type) {
					throw "Parameter '$name' must have Type specified"
				}

				$sqlParam = $sqlCmd.Parameters.Add("@$name", $param.Type)

				if ($param.Size -gt 0) {
					$sqlParam.Size = $param.Size
				}
				if ($param.Precision -gt 0) {
					$sqlParam.Precision = $param.Precision
				}
				if ($param.Scale -gt 0) {
					$sqlParam.Scale = $param.Scale
				}

				$sqlParam.Value = if ($null -eq $param.Value) {
					[DBNull]::Value
				}
				else {
					$param.Value
				}
			}
		}

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
