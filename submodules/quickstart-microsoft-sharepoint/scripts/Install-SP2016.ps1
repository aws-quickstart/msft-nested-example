[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$SQLServer,

    [Parameter(Mandatory=$true)]
    [string]$SPFarmAccount,

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [Parameter(Mandatory=$true)]
    [string]$Key,

    [Parameter(Mandatory=$true)]
    [ValidateSet("WebFrontEnd","Application","DistributedCache","Search","SingleServerFarm","Custom")]
    [string]$ServerRole,

    [Parameter(Mandatory=$false)]
    [switch]$CreateFarm,

    [Parameter(Mandatory=$false)]
    [switch]$StreamlinedTopology
)

try {
    $ErrorActionPreference = "Stop"

    Start-Transcript -Path c:\cfn\log\Install-SP2016.ps1.txt -Append

    if($Key -ne "NQGJR-63HC8-XCRQH-MYVCH-3J3QR"){
        $config = cat C:\cfn\scripts\config2016.xml
        $config = $config.replace("NQGJR-63HC8-XCRQH-MYVCH-3J3QR",$Key)
        Set-Content -Path C:\cfn\scripts\config2016.xml -Value $config
    }

    $driveLetter = Get-Volume | ?{$_.DriveType -eq 'CD-ROM'} | select -ExpandProperty DriveLetter
    if ($driveLetter.Count -gt 1) {
        throw "More than 1 mounted ISO found"
    }

    Start-Process "$($driveLetter):\setup.exe" -ArgumentList '/config c:\cfn\scripts\config2016.xml' -Wait

    New-Item HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo\ -EA 0
    New-ItemProperty HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo\ -Name SQL -Value "DBMSSOCN,$SQLServer"

    $pass = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $SPFarmAccount,$pass

    Add-PSSnapin *sharepoint*
    if($CreateFarm) {
        $newSPConfigurationDatabaseParams = @{
            LocalServerRole = $ServerRole
            DatabaseServer = "SQL"
            DatabaseName = "SPConfigDB"
            AdministrationContentDatabaseName = "AdminDB"
            PassPhrase = $(ConvertTo-SecureString $Password -AsPlainText -Force)
            FarmCredentials = $cred
        }

        if ($StreamlinedTopology -and $ServerRole -ne "DistributedCache") {
            $newSPConfigurationDatabaseParams.Add("SkipRegisterAsDistributedCacheHost",$true)
        }

        New-SPConfigurationDatabase @newSPConfigurationDatabaseParams
        New-SPCentralAdministration –Port 18473 –WindowsAuthProvider NTLM
    }
    else {
        $connectSPConfigurationDatabaseParams = @{
            LocalServerRole = $ServerRole
            DatabaseServer = "SQL"
            DatabaseName = "SPConfigDB"
            PassPhrase = $(ConvertTo-SecureString $Password -AsPlainText -Force)
        }

        if ($StreamlinedTopology -and $ServerRole -ne "DistributedCache") {
            $connectSPConfigurationDatabaseParams.Add("SkipRegisterAsDistributedCacheHost",$true)
        }

        Connect-SPConfigurationDatabase @connectSPConfigurationDatabaseParams
    }

    Install-SPHelpCollection -All
    Initialize-SPResourceSecurity
    Install-SPService
    Install-SPFeature -AllExistingFeatures –Force
    Install-SPApplicationContent

    $timerServiceName = "SPTimerV4"
    $timerService = Get-Service $timerServiceName
    if ($timerService.Status -ne "Running") {
        Start-Service $timerServiceName
    }
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}