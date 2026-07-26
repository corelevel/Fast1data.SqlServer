Remove-Module Fast1data.SqlServer -ErrorAction Ignore

Import-Module "$PSScriptRoot\..\..\Fast1data.SqlServer\Fast1data.SqlServer.psd1" -Force -Verbose

Invoke-Fast1Migration `
	-ConnStr 'Data Source=(local);Initial Catalog=tempdb;Connection Timeout=5;Encrypt=False;
		Encrypt=False;TrustServerCertificate=true;Integrated Security=True;Application Name=Fast1data.SqlServer;' `
	-BasePath $PSScriptRoot `
	-Phase 'phase01' `
	-ForceScripts 'job007/000-kill-all-user-processes.sql' `
	-Verbose `
	#-WhatIf