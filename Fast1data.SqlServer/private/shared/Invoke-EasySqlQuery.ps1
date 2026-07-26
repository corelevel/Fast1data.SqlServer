using module ./EasySqlParam.psm1

<#
.SYNOPSIS
Executes a parameterized SQL command.

.DESCRIPTION
Creates a Microsoft.Data.SqlClient command on an existing connection, adds
parameters described by EasySqlParam values, and executes the command as either
a non-query or scalar operation.

.PARAMETER SqlConn
Specifies an open Microsoft.Data.SqlClient connection.

.PARAMETER Query
Specifies the SQL text or stored-procedure name to execute.

.PARAMETER CommandType
Specifies whether Query contains SQL text or a stored-procedure name.

.PARAMETER Parameters
Specifies command parameters keyed by parameter name. Each value must be an
EasySqlParam instance.

.PARAMETER Scalar
Returns the first column of the first result row instead of executing the
command as a non-query.
#>
function Invoke-EasySqlQuery {
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

	$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn)
	$sqlCmd.CommandType = $CommandType

	if ($Parameters) {
		foreach ($name in $Parameters.Keys) {
			$param = $Parameters[$name]

			if ($param -isnot [EasySqlParam]) {
				throw "Parameter '$name' must be of type EasySqlParam"
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

	try {
		if ($Scalar) {
			return $sqlCmd.ExecuteScalar()
		}

		[void]$sqlCmd.ExecuteNonQuery()
	}
	finally {
		$sqlCmd.Dispose()
	}
}
