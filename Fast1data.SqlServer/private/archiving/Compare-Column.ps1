using module ./Metadata.psm1

<#
.SYNOPSIS
Compares source and destination table columns.

.DESCRIPTION
Validates compatible data types and logs differences in collation, computed
state, nullability, and missing columns.

.PARAMETER SrcColumns
Specifies source columns keyed by column name.

.PARAMETER DstColumns
Specifies destination columns keyed by column name.

.PARAMETER LogFile
Specifies an optional log file for comparison messages.
#>
function Compare-Column {
	param (
		[Parameter(Mandatory)]
		[System.Collections.Generic.Dictionary[string, TableColumn]]$SrcColumns,

		[Parameter(Mandatory)]
		[System.Collections.Generic.Dictionary[string, TableColumn]]$DstColumns,

		[string]$LogFile
	)

	foreach ($srcColumn in $SrcColumns.Values) {
		$dstColumn = $null
		$found = $DstColumns.TryGetValue($srcColumn.Name, [ref]$dstColumn)
		if ($found) {
			if ($dstColumn.DataType -ne $srcColumn.DataType) {
				throw "Column [$($srcColumn.Name)] data type doesn't match in source and target tables"
			}
			if ($dstColumn.Collation -ne $srcColumn.Collation) {
				Write-LogMessage -Message "Collation attribute for the column [$($srcColumn.Name)] doesn't match in source and target tables" `
					-LogFile $LogFile -Level Warning
			}
			if ($dstColumn.Computed -ne $srcColumn.Computed) {
				Write-LogMessage -Message "Computed attribute for the column [$($srcColumn.Name)] doesn't match in source and target tables" `
					-LogFile $LogFile -Level Warning
			}
			if ($dstColumn.Nullable -ne $srcColumn.Nullable) {
				Write-LogMessage -Message "Nullability attribute for the column [$($srcColumn.Name)] doesn't match in source and target tables" `
					-LogFile $LogFile -Level Warning
			}
		}
		elseif ($srcColumn.Computed) {
			Write-LogMessage -Message "Computed column [$($srcColumn.Name)] doesn't exist in the destination table" `
				-LogFile $LogFile -Level Warning
		}
		else {
			Write-LogMessage -Message "Column [$($srcColumn.Name)] doesn't exist in the destination table" `
				-LogFile $LogFile
		}
	}
}
