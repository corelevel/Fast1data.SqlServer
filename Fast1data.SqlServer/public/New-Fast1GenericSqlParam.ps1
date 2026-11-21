using module ../private/shared/GenericSqlParam.psm1

<#
.SYNOPSIS
Creates a typed SQL input parameter descriptor without executing SQL.

.DESCRIPTION
Returns one descriptor for either public SQL query command. Ordinary root module
import is sufficient. Values retain their native representation, including binary
arrays. Omitted or null Value binds as SQL NULL. This factory allocates no SQL
resources. Parameters supplied to query commands use names without a leading @.
Supports WhatIf and Confirm for descriptor creation. WhatIf emits no descriptor.

.PARAMETER Type
Required SQL type. BigInt and enum zero are valid; null and invalid types fail binding.

.PARAMETER Value
Native input value. Omitted or explicit null represents typed SQL NULL.

.PARAMETER Size
Nonnegative size, up to Int32.MaxValue. Only positive values are forwarded;
zero retains the provider default. MAX size -1 is not supported.

.PARAMETER Precision
Byte precision. Only positive values are forwarded; zero retains provider inference.

.PARAMETER Scale
Byte scale. Only positive values are forwarded. Zero retains provider inference
and does not force decimal scale zero. Output parameters are not supported.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
GenericSqlParam. One typed input descriptor accepted by both query commands.

.EXAMPLE
$parameters = @{ Id = New-Fast1GenericSqlParam -Type BigInt -Value 42 }
Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'SELECT @Id' -Parameters $parameters -Scalar

Uses an already-open caller-owned connection for scalar execution.

.EXAMPLE
$typedNull = New-Fast1GenericSqlParam -Type NVarChar -Size 100

Creates a typed SQL NULL without opening a connection or executing SQL.
#>
function New-Fast1GenericSqlParam {
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNull()]
		[System.Data.SqlDbType]$Type,

		[AllowNull()]
		[object]$Value,

		[ValidateRange(0, [int]::MaxValue)]
		[int]$Size = 0,

		[byte]$Precision = 0,
		[byte]$Scale = 0
	)

	if ($PSCmdlet.ShouldProcess('SQL input parameter descriptor', 'Create')) {
		[GenericSqlParam]@{
			Type = $Type
			Value = $Value
			Size = $Size
			Precision = $Precision
			Scale = $Scale
		}
	}
}
