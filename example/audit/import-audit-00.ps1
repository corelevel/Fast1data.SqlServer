Remove-Module Fast1data.SqlServer -ErrorAction Ignore

Import-Module "$PSScriptRoot\..\..\Fast1data.SqlServer\Fast1data.SqlServer.psd1" -Force -Verbose

Invoke-Fast1Audit -ConnStr 'Data Source=(local);Initial Catalog=fast1_audit;Connection Timeout=5;
	Encrypt=False;TrustServerCertificate=true;Integrated Security=True;Application Name=Fast1data.SqlServer;' `
	-Folder 'C:\Temp' `
	-Verbose
