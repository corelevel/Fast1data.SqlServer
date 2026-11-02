function Get-SharedHelperPublicContract {
	[CmdletBinding()]
	param ([Parameter(Mandatory)][string]$DistributionRoot)

	$manifest = Import-PowerShellDataFile (Join-Path $DistributionRoot 'Fast1data.SqlServer.psd1')
	$commands = foreach ($name in $manifest.FunctionsToExport | Sort-Object) {
		$command = Get-Command $name -Module Fast1data.SqlServer
		$parameters = foreach ($parameter in $command.Parameters.Values | Sort-Object Name) {
			$attributes = foreach ($attribute in $parameter.Attributes) {
				$properties = [ordered]@{}
				foreach ($property in $attribute.PSObject.Properties | Sort-Object Name) {
					$properties[$property.Name] = @($property.Value | ForEach-Object { [string]$_ })
				}
				[ordered]@{ Type = $attribute.GetType().FullName; Properties = $properties }
			}
			[ordered]@{
				Name = $parameter.Name
				Type = $parameter.ParameterType.FullName
				Aliases = @($parameter.Aliases)
				Attributes = @($attributes)
			}
		}
		[ordered]@{
			Name = $name
			CmdletBinding = $command.CmdletBinding
			CommandAttributes = @($command.ScriptBlock.Ast.Body.ParamBlock.Attributes | ForEach-Object { $_.Extent.Text })
			DefaultParameterSet = $command.DefaultParameterSet
			Declaration = $command.ScriptBlock.Ast.Body.ParamBlock.Extent.Text.Replace("`r`n", "`n")
			Parameters = @($parameters)
			ParameterSets = @($command.ParameterSets | ForEach-Object { $_.ToString() })
		}
	}
	[ordered]@{
		FunctionsToExport = @($manifest.FunctionsToExport | Sort-Object)
		AliasesToExport = @($manifest.AliasesToExport)
		VariablesToExport = @($manifest.VariablesToExport)
		CmdletsToExport = @($manifest.CmdletsToExport)
		PowerShellVersion = [string]$manifest.PowerShellVersion
		CompatiblePSEditions = @($manifest.CompatiblePSEditions)
		Commands = @($commands)
	} | ConvertTo-Json -Depth 20
}
