# PSProxyEvents
PSProxyEvents is a PowerShell module that allows users to extend functionality for existing PowerShell commands.

## Usage

```powershell
PS> Import-Module -Name <Module Path> -Force;
PS> Register-ProxyEvent -CommandName 'Get-ChildItem' -ScriptBlock { Write-Host -Object $Path } -Before;
PS> Get-ChildItem -Path 'C:\';
C:\

        Directory: C:\


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
d----         8/20/2020  12:37 PM                Logs
d----         12/7/2019   1:14 AM                PerfLogs
d-r--         9/13/2021   9:53 PM                Program Files
d-r--          8/7/2021   9:49 PM                Program Files (x86)
d----         8/20/2020  11:53 AM                Temp
d-r--         8/20/2020   9:20 AM                Users
d----         9/17/2021   1:10 AM                Windows
```
