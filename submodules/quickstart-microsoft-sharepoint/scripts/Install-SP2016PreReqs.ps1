try {
    $ErrorActionPreference = "Stop"

    Start-Transcript -Path c:\cfn\log\Install-SP2016PreReqs.ps1.txt -Append

    # because of https://community.spiceworks.com/topic/1991530-fixed-sharepoint-2016-never-installs-pre-requisites-properly
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer -Force -ErrorAction silentlycontinue

    $driveLetter = Get-Volume | ?{$_.DriveType -eq 'CD-ROM'} | select -ExpandProperty DriveLetter
    if ($driveLetter.Count -gt 1) {
        throw "More than 1 mounted ISO found"
    }

    Start-Process "$($driveLetter):\prerequisiteinstaller.exe" -ArgumentList '/unattended' -Wait

    Restart-Computer
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}
