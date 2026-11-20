# Bind typed descriptors silently, preserving native values and provider defaults.
function Add-GenericSqlParameter {
	param ($SqlCmd, [hashtable]$Parameters)
	if ($Parameters) {
		foreach ($name in $Parameters.Keys) {
			$param = $Parameters[$name]

			if ($param -isnot [GenericSqlParam]) {
				throw "Parameter '$name' must be of type GenericSqlParam"
			}

			if ($null -eq $param.Type) {
				throw "Parameter '$name' must have Type specified"
			}

			$sqlParam = $SqlCmd.Parameters.Add("@$name", $param.Type)

			if ($param.Size -gt 0) {
				$sqlParam.Size = $param.Size
			}
			if ($param.Precision -gt 0) {
				$sqlParam.Precision = $param.Precision
			}
			if ($param.Scale -gt 0) {
				$sqlParam.Scale = $param.Scale
			}

			$sqlParam.Value = $param.Value
			if ($null -eq $param.Value) {
				$sqlParam.Value = [DBNull]::Value
			}
		}
	}

}

<#
.SYNOPSIS
Creates a SQL command for an existing connection.

.DESCRIPTION
Constructs a Microsoft.Data.SqlClient.SqlCommand with the supplied query and
connection. The command is returned without opening the connection or executing
the query. The caller is responsible for disposing the command. This helper also
allows tests to substitute a controlled command for Invoke-Fast1GenericSqlQuery.

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
Invoke-Fast1GenericSqlQuery
#>
function Get-GenericSqlCommand {
	param ([string]$Query, [Microsoft.Data.SqlClient.SqlConnection]$SqlConn)
	[Microsoft.Data.SqlClient.SqlCommand]::new($Query, $SqlConn)
}
