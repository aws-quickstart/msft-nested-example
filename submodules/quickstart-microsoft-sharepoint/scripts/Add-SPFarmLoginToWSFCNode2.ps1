[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$SPFarmAccount,

    [Parameter(Mandatory=$true)]
    [string]$ADServer1NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode2NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,

    [Parameter(Mandatory=$true)]
    [string]$DomainAdminPassword
)

try {
    $ErrorActionPreference = "Stop"

    Start-Transcript -Path c:\cfn\log\Add-SPFarmLoginToWSFCNode2.ps1.txt -Append

    $pass = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("$DomainNetBIOSName\$DomainAdminUser", $pass)

    #force AD replication from DC1
    Invoke-Command -ScriptBlock {
        repadmin /syncall /A /e /P
    } -ComputerName $ADServer1NetBIOSName -Credential $cred


    #need to add sql server roles for spfarm account on 2nd sql node
    #create sql script and invoke on 2nd SQL node
    $scriptBlock = {
        param ($DomainNetBIOSName, $SPFarmAccount)

        Invoke-SqlCmd -Query "USE [master];CREATE LOGIN [$DomainNetBIOSName\$SPFarmAccount] FROM WINDOWS WITH DEFAULT_DATABASE=[master];ALTER SERVER ROLE [dbcreator] ADD MEMBER [$DomainNetBIOSName\$SPFarmAccount];ALTER SERVER ROLE [securityadmin] ADD MEMBER [$DomainNetBIOSName\$SPFarmAccount]"
        #Invoke-SqlCmd -inputfile c:\cfn\scripts\spfarm_login.sql
    }

    Invoke-Command -ScriptBlock $scriptBlock -ComputerName $WSFCNode2NetBIOSName -Credential $cred -ArgumentList $DomainNetBIOSName, $SPFarmAccount
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}