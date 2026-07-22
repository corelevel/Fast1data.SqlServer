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
		[guid[]]$AuditGuids
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

		$importStatesMap = @{}

		while ($sqlReader.Read()) {
			$importStatesMap[$sqlReader['audit_guid']] = [PSCustomObject]@{
				FileName = $sqlReader['file_name']
				AuditRecordOffset = $sqlReader['audit_record_offset']
				}
		}

		$importStatesMap
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

function Import-SqlAuditFiles {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[Microsoft.Data.SqlClient.SqlConnection]$SqlConn,

		[Parameter(Mandatory)]
		[string]$FileName,

		[bigint]$RecordOffset
	)

	$sqlCmd = $null
	$sqlReader = $null

	try {
		$tvp = New-Object System.Data.DataTable
		[void]$tvp.Columns.Add("value", [Guid])

		foreach ($guid in $AuditGuids) {
			[void]$tvp.Rows.Add($guid)
		}

		$sqlCmd = [Microsoft.Data.SqlClient.SqlCommand]::new('dbo.stp_import_audit_files', $SqlConn)
		$sqlCmd.CommandType = [System.Data.CommandType]::StoredProcedure
		$sqlCmd.Parameters.Add("@file_pattern", [System.Data.SqlDbType]::NVarChar, 260).Value = $FileName
		$sqlReader = $sqlCmd.ExecuteNonQuery()
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

function Invoke-EasyAudit {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$Folder,

		[string]$LogFile
	)

	Set-StrictMode -Version Latest

	$sqlConn = $null
	try {
		$auditFiles = Get-SqlAuditFiles -Folder $Folder
		if (-not $auditFiles) {
			Write-LogMessage -Message "No audit files found in $Folder"	`
				-LogFile $LogFile
			return
		}
		$auditsToProcess = $auditFiles.AuditGuid |
			Sort-Object -Unique |
			ForEach-Object {
				[PSCustomObject]@{
					AuditGuid  = $_
					IsProcessed = $false
				}
			}

		$sqlConn = [Microsoft.Data.SqlClient.SqlConnection]::new()
		$sqlConn.ConnectionString = $ConnStr
		$sqlConn.Open()

		$importStatesMap = Get-ImportState -SqlConn $sqlConn -AuditGuids ([Guid[]]$auditsToProcess.AuditGuid)

		foreach($audit in $auditsToProcess) {
			if ($audit.IsProcessed) {
				continue
			}
			if ($importStatesMap.ContainsKey($auditFile.AuditGuid)) {
				
			}
			else {

			}
		}
	}
	finally {
		if ($null -ne $sqlConn) {
			$sqlConn.Close()
			$sqlConn.Dispose()
		}
	}

}

Import-SqlClient