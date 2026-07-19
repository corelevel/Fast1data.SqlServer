using namespace System.Collections.Generic

function Import-SqlClient {
	[CmdletBinding()]
	param()

	if ([AppDomain]::CurrentDomain.GetAssemblies().GetName().Name -contains 'Microsoft.Data.SqlClient') {
		return
	}

	$rid = Get-RuntimeIdentifier
	$sqlClientDll = Join-Path $PSScriptRoot "lib\$rid\Microsoft.Data.SqlClient.dll"

	if (-not (Test-Path $sqlClientDll)) {
		throw "Microsoft.Data.SqlClient was not found for runtime '$rid'. Expected: $sqlClientDll"
	}

	[System.Reflection.Assembly]::LoadFrom($sqlClientDll) | Out-Null
}

function Get-RuntimeIdentifier {
	[CmdletBinding()]
	param()

	$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

	switch ($true) {
		$IsWindows {
			switch ($architecture) {
				([System.Runtime.InteropServices.Architecture]::X64) { return 'win-x64' }
				([System.Runtime.InteropServices.Architecture]::Arm64) { return 'win-arm64' }
				default { throw "Unsupported Windows architecture: $architecture" }
			}
		}

		$IsLinux {
			switch ($architecture) {
				([System.Runtime.InteropServices.Architecture]::X64) { return 'linux-x64' }
				([System.Runtime.InteropServices.Architecture]::Arm64) { return 'linux-arm64' }
				default { throw "Unsupported Linux architecture: $architecture" }
			}
		}

		$IsMacOS {
			switch ($architecture) {
				([System.Runtime.InteropServices.Architecture]::X64) { return 'osx-x64' }
				([System.Runtime.InteropServices.Architecture]::Arm64) { return 'osx-arm64' }
				default { throw "Unsupported macOS architecture: $architecture" }
			}
		}

		default {
			throw "Unsupported operating system."
		}
	}
}

function Write-LogMessage {
	[CmdletBinding()]
	param(
		[parameter(Mandatory)]
		[string]$Message,

		[string]$LogFile,
		
		[ValidateSet('Info','Warning','Error')]
		[string]$Level = 'Info'
	)

	$line = "$((Get-Date).ToString('[MM/dd/yy HH:mm:ss.ff]')) [$Level] $Message"

	if ($Level -eq 'Warning') {
		Write-Warning $line
	}
	elseif ($Level -eq 'Error') {
		Write-Error $line
	}
	else {
		Write-Verbose $line
	}

	if ($LogFile) {
		Add-Content -Path $LogFile -Value $line
	}
}
function Get-SqlAuditFiles {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$Folder
	)

	$regex = '^(?<AuditName>.+?)_(?<AuditGuid>[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})_(?<Sequence>\d+)_(?<Ticks>\d+)\.sqlaudit$'

	Get-ChildItem -Path $Folder -Filter '*.sqlaudit' -File | ForEach-Object {
		if ($_.Name -match $regex) {
			[PSCustomObject]@{
				DirectoryName = $_.DirectoryName
				FileName      = $_.FullName
				BaseFileName  = $Matches.AuditName
				AuditGuid     = [Guid]$Matches.AuditGuid
			}
		}
	}
}

function Get-ImportState {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[Microsoft.Data.SqlClient.SqlConnection]$SqlConn,

		[Parameter(Mandatory)]
		[array]$AuditGuids
	)

	$sqlCmd = $null
	$sqlReader = $null

	try {
		$tvp = New-Object System.Data.DataTable
		[void]$tvp.Columns.Add("value", [Guid])

		foreach ($guid in $AuditGuids) {
			[void]$tvp.Rows.Add($guid)
		}

		$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_get_import_state', $SqlConn)
		$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
		$p = $sqlCmd.Parameters.Add("@audit_guids", [System.Data.SqlDbType]::Structured)
        $p.TypeName = "dbo.guid_array"
        $p.Value = $tvp
		$sqlReader = $sqlCmd.ExecuteReader()

		while ($sqlReader.Read()) {
			[PSCustomObject]@{
				FileName = $sqlReader['file_name']
				AuditFileOffset = $sqlReader['audit_file_offset']
			}
		}
	}
	finally {
		if ($null -ne $sqlReader) {
			$sqlReader.Close()
			$sqlReader.Dispose()
		}
		if ($null -ne $sqlCmd) {
			$sqlCmd.Dispose()
		}
	}
}

function Import-SqlAudit {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$Folder
	)

	$sqlConn = $null
	try {
		$auditFiles = Get-SqlAuditFiles -Folder $Folder
		$auditGuid = $auditFiles.AuditGuid | Sort-Object -Unique

		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr

		$sqlConn.Open()

		$state = @(Get-ImportState -SqlConn $sqlConn -AuditGuids $auditGuid)
		$state.Count
	}
	finally {
		if ($null -ne $sqlConn) {
			$sqlConn.Close()
			$sqlConn.Dispose()
		}
	}

}

Import-SqlClient