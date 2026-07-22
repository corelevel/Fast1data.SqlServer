Remove-Module easy-audit -ErrorAction Ignore

Import-Module "$PSScriptRoot\..\easy-audit.psd1" -Force -Verbose

try {
	Invoke-EasyAudit -ConnStr 'Data Source=(local);Initial Catalog=easy_audit;Connection Timeout=5;
		Encrypt=False;TrustServerCertificate=true;User Id=sa;Password=P1s-Unsee-Me;Application Name=audit;' `
		-Folder 'C:\Temp' `
		-Verbose
}
catch {
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
}
