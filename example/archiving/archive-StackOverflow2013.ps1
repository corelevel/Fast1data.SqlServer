Remove-Module Fast1data.SqlServer -ErrorAction Ignore

Import-Module "$PSScriptRoot\..\..\Fast1data.SqlServer\Fast1data.SqlServer.psd1" -Force -Verbose

Invoke-Fast1Archiving -ConnStr 'Data Source=(local);Initial Catalog=fast1-archiving;Connection Timeout=5;
    Encrypt=False;User Id=sa;Password=P1s-Unsee-Me;Application Name=Fast1data.SqlServer;' `
    -GroupName 'group01' `
    -Verbose
