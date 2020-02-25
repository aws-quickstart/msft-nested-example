Configuration SharePointServer {

    $password = ConvertTo-SecureString 'ThisWillLoadAtRunTime' -AsPlainText -Force
    $SPSetupAccount            = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPSetupAccount}', $password)
    $FarmAccount               = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPFarmAccount}', $password)
    $Passphrase                = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPPassPhrase}', $password)
    $ServicePoolManagedAccount = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPSvcAppAccount}', $password)
    $WebPoolManagedAccount     = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPWebAppAccount}', $password)
    $SuperUserAccount          = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPSuperUserAccount}', $password)
    $SuperReaderAccount        = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPReaderAccount}', $password)
    $UPSyncAccount             = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPUPSyncAccount}', $password)
    $CrawlAccount              = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SPCrawlAccount}', $password)
    $domainAdminCredential     = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${ADAdminSecret}', $password)
    $sqlAdminCredential        = New-Object -TypeName "System.Management.Automation.PSCredential" `
                                            -ArgumentList @('${SQLAdminSecret}', $password)

    Import-DscResource -ModuleName xCredSSP              -ModuleVersion 1.0.1
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion 6.2.0.0
    Import-DscResource -ModuleName StorageDsc            -ModuleVersion 4.6.0.0
    Import-DscResource -ModuleName xActiveDirectory      -ModuleVersion 2.25.0.0
    Import-DscResource -ModuleName SharePointDsc         -ModuleVersion 3.4.0.0
    Import-DscResource -ModuleName xWebAdministration    -ModuleVersion 2.5.0.0

    node localhost {

        Environment VersionStamp {
            Name = "SPQuickStartPrefix"
            Value = '${GenerateUsernames.prefix}'
        }

        # Putting this before the domain join means that the copy from S3 has time to succeed before the domain join reboot
        Script WaitForBinaries {
            GetScript = { return @{} }
            TestScript = {
                return (Get-Item C:\config\sources\installer.zip -ErrorAction SilentlyContinue).Length -ne 0
            }
            SetScript = {
                $count = 0
                while ((Get-Item C:\config\sources\installer.zip -ErrorAction SilentlyContinue).Length -eq 0 -and $count -lt 10) {
                    $count++
                    Start-Sleep -Seconds 30
                }
            }
        }

        Computer DomainJoin {
            Name = "{tag:Name}"
            DomainName = '${DomainDNSName}'
            Credential = $domainAdminCredential
            DependsOn = "[Script]WaitForBinaries"
        }

        Disk SecondaryDisk {
            DiskId = 1
            DriveLetter = 'D'
            PartitionStyle = 'MBR'
            FSFormat = 'NTFS'
        }

        Registry DisableIPv6 
        {
            Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
            ValueName = "DisabledComponents"
            ValueData = "ff"
            ValueType = "Dword"
            Hex       = $true
            Ensure    = 'Present'
        }

        Archive UnzipSpInstaller
        {
            Path        = "C:\config\sources\installer.zip"
            Destination = "D:\binaries"
            Ensure      = "Present"
            DependsOn   = "[Disk]SecondaryDisk", '[Registry]DisableIPv6'
        }

        xCredSSP CredSSPServer 
        { 
            Ensure = "Present" 
            Role = "Server" 
            DependsOn = "[Computer]DomainJoin"
        } 

        xCredSSP CredSSPClient 
        { 
            Ensure = "Present" 
            Role = "Client" 
            DelegateComputers = '*.${DomainDNSName}'
            DependsOn = "[Computer]DomainJoin"
        }

        @(
            "RSAT-ADDS", 
            "RSAT-AD-AdminCenter", 
            "RSAT-ADDS-Tools", 
            "RSAT-AD-PowerShell" 
        ) | ForEach-Object -Process {
            WindowsFeature "Feature-$_"
            { 
                Ensure = "Present" 
                Name = $_
            }
        }

        $userAccounts = @{
            "setup" = $SPSetupAccount
            "farm" = $FarmAccount
            "web" = $WebPoolManagedAccount
            "svc" = $ServicePoolManagedAccount
            "crawl" = $CrawlAccount
            "sync" = $UPSyncAccount
            "super" = $SuperUserAccount
            "reader" = $SuperReaderAccount
        }

        $userAccounts.Keys | ForEach-Object -Process {
            xADUser "User-$_"
            { 
                DomainName = '${DomainDNSName}'
                DomainAdministratorCredential = $domainAdminCredential 
                UserName = "`${GenerateUsernames.$_}" 
                Password = $userAccounts[$_]
                Ensure = "Present" 
                DependsOn = "[WindowsFeature]Feature-RSAT-AD-PowerShell" 
            }
        }

        Group LocalAdministrators
        {
            GroupName        = "Administrators"
            Ensure           = "Present"
            MembersToInclude = '${DomainNetBIOSName}\${GenerateUsernames.setup}'
            Credential       = $domainAdminCredential
            DependsOn        = @("[xADUser]User-svc", "[Computer]DomainJoin")
        }

        SPInstallPrereqs InstallPrereqs 
        {
            Ensure           = "Present"
            OnlineMode       = $true
            InstallerPath    = "D:\binaries\prerequisiteinstaller.exe"
            IsSingleInstance = "Yes"
            DependsOn        = "[Group]LocalAdministrators" 
        }

        xWebAppPool RemoveDotNet2Pool         { Name      = ".NET v2.0"            
                                                Ensure    = "Absent" 
                                                DependsOn = "[SPInstallPrereqs]InstallPrereqs" }
        xWebAppPool RemoveDotNet2ClassicPool  { Name      = ".NET v2.0 Classic"
                                                Ensure    = "Absent"
                                                DependsOn = "[SPInstallPrereqs]InstallPrereqs" }
        xWebAppPool RemoveDotNet45Pool        { Name      = ".NET v4.5"
                                                Ensure    = "Absent"
                                                DependsOn = "[SPInstallPrereqs]InstallPrereqs" }
        xWebAppPool RemoveDotNet45ClassicPool { Name      = ".NET v4.5 Classic"
                                                Ensure    = "Absent"
                                                DependsOn = "[SPInstallPrereqs]InstallPrereqs" }
        xWebAppPool RemoveClassicDotNetPool   { Name      = "Classic .NET AppPool"
                                                Ensure = "Absent"
                                                DependsOn = "[SPInstallPrereqs]InstallPrereqs" }
        xWebAppPool RemoveDefaultAppPool      { Name      = "DefaultAppPool"
                                                Ensure    = "Absent"
                                                DependsOn = "[SPInstallPrereqs]InstallPrereqs" }
        xWebSite    RemoveDefaultWebSite      { Name         = "Default Web Site"
                                                Ensure       = "Absent"
                                                PhysicalPath = "C:\inetpub\wwwroot"
                                                DependsOn    = "[SPInstallPrereqs]InstallPrereqs" }

        SPInstall InstallSharePoint 
        {
            Ensure           = "Present"
            BinaryDir        = "D:\binaries"
            ProductKey       = '${SPProductKey}'
            DependsOn        = "[SPInstallPrereqs]InstallPrereqs"
            IsSingleInstance = "Yes"
        }

        Script SetMAXDOP
        {
            DependsOn = "[SPInstall]InstallSharePoint"
            PsDscRunAsCredential = $sqlAdminCredential
            GetScript = {return @{}}
            TestScript = {
                $conn = new-object system.data.SqlClient.SQLConnection("Data Source=`${SPDatabaseName}; Integrated Security=SSPI; Initial Catalog=master")
                $cmd = new-object system.data.sqlclient.sqlcommand('EXEC sp_configure ''show advanced options'', 1; RECONFIGURE; EXEC sp_configure ''max degree of parallelism'';',$conn)
                $conn.Open()
                $a = New-Object System.Data.sqlclient.sqlDataAdapter $cmd
                $ds = New-Object System.Data.DataSet
                $a.Fill($ds) | Out-Null
                $conn.Close()
                if ($ds.Tables[0].Rows.Count -ne 1) {return $false}
                if ($ds.Tables[0].Rows[0].run_value -ne 1) {return $false}
                return $true
            }
            SetScript = {
                $conn = new-object system.data.SqlClient.SQLConnection("Data Source=`${SPDatabaseName}; Integrated Security=SSPI; Initial Catalog=master")
                $cmd = new-object system.data.sqlclient.sqlcommand('EXEC sp_configure ''show advanced options'', 1; RECONFIGURE; EXEC sp_configure ''max degree of parallelism'', 1; RECONFIGURE;',$conn)
                $conn.Open()
                $cmd.ExecuteNonQuery()
                $conn.Close()
            }
        }

        Script SQLPermissions
        {
            DependsOn = "[SPInstall]InstallSharePoint"
            PsDscRunAsCredential = $sqlAdminCredential
            GetScript = {return @{}}
            TestScript = {
                $conn = new-object system.data.SqlClient.SQLConnection("Data Source=`${SPDatabaseName}; Integrated Security=SSPI; Initial Catalog=master")
                $cmd = new-object system.data.sqlclient.sqlcommand('SELECT spU.name,MAX(CASE WHEN srm.role_principal_id = 4 THEN 1 END) AS securityadmin,MAX(CASE WHEN srm.role_principal_id = 9 THEN 1 END) AS dbcreator FROM sys.server_principals AS spR JOIN sys.server_role_members AS srm ON spR.principal_id = srm.role_principal_id JOIN sys.server_principals AS spU ON srm.member_principal_id = spU.principal_id WHERE spR.[type] = ''R'' AND spU.name = ''${DomainNetBIOSName}\${GenerateUsernames.setup}'' GROUP BY spU.name',$conn)
                $conn.Open()
                $a = New-Object System.Data.sqlclient.sqlDataAdapter $cmd
                $ds = New-Object System.Data.DataSet
                $a.Fill($ds) | Out-Null
                $conn.Close()
                if ($ds.Tables[0].Rows.Count -ne 1) {return $false}
                if ($ds.Tables[0].Rows[0].securityadmin -ne 1) {return $false}
                if ($ds.Tables[0].Rows[0].dbcreator -ne 1) {return $false}
                return $true
            }
            SetScript = {
                $conn = new-object system.data.SqlClient.SQLConnection("Data Source=`${SPDatabaseName}; Integrated Security=SSPI; Initial Catalog=master")
                $cmd = new-object system.data.sqlclient.sqlcommand('CREATE LOGIN [${DomainNetBIOSName}\${GenerateUsernames.setup}] FROM WINDOWS; EXEC sp_addsrvrolemember ''${DomainNetBIOSName}\${GenerateUsernames.setup}'', ''dbcreator''; EXEC sp_addsrvrolemember ''${DomainNetBIOSName}\${GenerateUsernames.setup}'', ''securityadmin''; GRANT CONNECT SQL TO [${DomainNetBIOSName}\${GenerateUsernames.setup}];',$conn)
                $conn.Open()
                $cmd.ExecuteNonQuery()
                $conn.Close()
            }
        }

        SPFarm CreateSPFarm
        {
            Ensure                   = "Present"
            DatabaseServer           = '${SPDatabaseName}'
            FarmConfigDatabaseName   = '${GenerateUsernames.db}_Config'
            Passphrase               = $Passphrase
            FarmAccount              = $FarmAccount
            PsDscRunAsCredential     = $SPSetupAccount
            AdminContentDatabaseName = '${GenerateUsernames.db}_AdminContent'
            RunCentralAdmin          = $true
            IsSingleInstance         = "Yes"
            DependsOn                = "[Script]SQLPermissions"
        }

        SPAlternateUrl CentralAdminAAM
        {
            WebAppName           = "SharePoint Central Administration v4"
            Zone                 = "Intranet"
            Url                  = 'http://{tag:Name}.${DomainDNSName}:9999'
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }

        SPManagedAccount ServicePoolManagedAccount
        {
            AccountName          = '${DomainNetBIOSName}\${GenerateUsernames.svc}'
            Account              = $ServicePoolManagedAccount
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }
        SPManagedAccount WebPoolManagedAccount
        {
            AccountName          = '${DomainNetBIOSName}\${GenerateUsernames.web}'
            Account              = $WebPoolManagedAccount
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }
        SPDiagnosticLoggingSettings ApplyDiagnosticLogSettings
        {
            PsDscRunAsCredential                        = $SPSetupAccount
            LogPath                                     = "D:\ULS"
            LogSpaceInGB                                = 5
            AppAnalyticsAutomaticUploadEnabled          = $false
            CustomerExperienceImprovementProgramEnabled = $true
            DaysToKeepLogs                              = 7
            DownloadErrorReportingUpdatesEnabled        = $false
            ErrorReportingAutomaticUploadEnabled        = $false
            ErrorReportingEnabled                       = $false
            EventLogFloodProtectionEnabled              = $true
            EventLogFloodProtectionNotifyInterval       = 5
            EventLogFloodProtectionQuietPeriod          = 2
            EventLogFloodProtectionThreshold            = 5
            EventLogFloodProtectionTriggerPeriod        = 2
            LogCutInterval                              = 15
            LogMaxDiskSpaceUsageEnabled                 = $true
            ScriptErrorReportingDelay                   = 30
            ScriptErrorReportingEnabled                 = $true
            ScriptErrorReportingRequireAuth             = $true
            IsSingleInstance                            = "Yes"
            DependsOn                                   = "[SPFarm]CreateSPFarm"
        }
        SPUsageApplication UsageApplication 
        {
            Name                  = "Usage Service Application"
            DatabaseName          = '${GenerateUsernames.db}_Usage'
            UsageLogCutTime       = 5
            UsageLogLocation      = "D:\UsageLogs"
            UsageLogMaxFileSizeKB = 1024
            PsDscRunAsCredential  = $SPSetupAccount
            DependsOn             = "[SPFarm]CreateSPFarm"
        }
        SPStateServiceApp StateServiceApp
        {
            Name                 = "State Service Application"
            DatabaseName         = '${GenerateUsernames.db}_State'
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }
        SPDistributedCacheService EnableDistributedCache
        {
            Name                 = "AppFabricCachingService"
            Ensure               = "Present"
            CacheSizeInMB        = 1024
            ServiceAccount       = '${DomainNetBIOSName}\${GenerateUsernames.svc}'
            PsDscRunAsCredential = $SPSetupAccount
            CreateFirewallRules  = $true
            DependsOn            = @('[SPFarm]CreateSPFarm','[SPManagedAccount]ServicePoolManagedAccount')
        }

        #**********************************************************
        # Web applications
        #
        # This section creates the web applications in the 
        # SharePoint farm, as well as managed paths and other web
        # application settings
        #**********************************************************

        SPWebApplication SharePointSites
        {
            Name                   = "SharePoint Sites"
            ApplicationPool        = "SharePoint Sites"
            ApplicationPoolAccount = '${DomainNetBIOSName}\${GenerateUsernames.web}'
            AllowAnonymous         = $false
            DatabaseName           = '${GenerateUsernames.db}_Content'
            WebAppUrl              = 'http://{tag:Name}.${DomainDNSName}'
            HostHeader             = '{tag:Name}.${DomainDNSName}'
            Port                   = 80
            PsDscRunAsCredential   = $SPSetupAccount
            DependsOn              = "[SPManagedAccount]WebPoolManagedAccount"
        }

        #**********************************************************
        # This is here to account for a bug found in SharePoint 
        # 2019. Rebooting before creating the first site collection
        # appears to prevent an error from occuring.
        #**********************************************************
        Script RebootOnFirstRunOfWebApp
        {
            DependsOn = "[SPWebApplication]SharePointSites"
            GetScript = {return @{}}
            TestScript = {
                $value = Get-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                if ($null -eq $value) { return $false }
                if ($value.SPWebAppReboot -eq $true) { return $true }
                return $false
            }
            SetScript = {
                New-Item -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                Set-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -Name SPWebAppReboot -Value $true
                $global:DSCMachineStatus = 1
            }
        }

        SPCacheAccounts WebAppCacheAccounts
        {
            WebAppUrl              = 'http://{tag:Name}.${DomainDNSName}'
            SuperUserAlias         = '${DomainNetBIOSName}\${GenerateUsernames.super}'
            SuperReaderAlias       = '${DomainNetBIOSName}\${GenerateUsernames.reader}'
            PsDscRunAsCredential   = $SPSetupAccount
            DependsOn              = "[SPWebApplication]SharePointSites"
        }

        #**********************************************************
        # Service instances
        #
        # This section describes which services should be running
        # and not running on the server
        #**********************************************************

        SPServiceInstance ClaimsToWindowsTokenServiceInstance
        {  
            Name                 = "Claims to Windows Token Service"
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }   

        SPServiceInstance SecureStoreServiceInstance
        {  
            Name                 = "Secure Store Service"
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }
        
        SPServiceInstance ManagedMetadataServiceInstance
        {  
            Name                 = "Managed Metadata Web Service"
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }

        SPServiceInstance BCSServiceInstance
        {  
            Name                 = "Business Data Connectivity Service"
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }
        
        SPServiceInstance SearchServiceInstance
        {  
            Name                 = "SharePoint Server Search"
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }

        SPServiceInstance CentralAdmin
        {  
            Name                 = "Central Administration"
            Ensure               = "Present"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }
        
        #**********************************************************
        # Service applications
        #
        # This section creates service applications and required
        # dependencies
        #**********************************************************

        $serviceAppPoolName = "SharePoint Service Applications"
        SPServiceAppPool MainServiceAppPool
        {
            Name                 = $serviceAppPoolName
            ServiceAccount       = '${DomainNetBIOSName}\${GenerateUsernames.svc}'
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn            = "[SPFarm]CreateSPFarm"
        }

        SPSecureStoreServiceApp SecureStoreServiceApp
        {
            Name                  = "Secure Store Service Application"
            ApplicationPool       = $serviceAppPoolName
            AuditingEnabled       = $true
            AuditlogMaxSize       = 30
            DatabaseName          = '${GenerateUsernames.db}_SecureStore'
            PsDscRunAsCredential  = $SPSetupAccount
            DependsOn             = "[SPServiceAppPool]MainServiceAppPool"
        }
        
        SPManagedMetaDataServiceApp ManagedMetadataServiceApp
        {  
            Name                 = "Managed Metadata Service Application"
            PsDscRunAsCredential = $SPSetupAccount
            ApplicationPool      = $serviceAppPoolName
            DatabaseName         = '${GenerateUsernames.db}_MMS'
            DependsOn            = "[SPServiceAppPool]MainServiceAppPool"
        }

        SPBCSServiceApp BCSServiceApp
        {
            Name                  = "BCS Service Application"
            ApplicationPool       = $serviceAppPoolName
            DatabaseName          = '${GenerateUsernames.db}_BCS'
            DatabaseServer        = '${SPDatabaseName}'
            PsDscRunAsCredential  = $SPSetupAccount
            DependsOn             = @('[SPServiceAppPool]MainServiceAppPool', '[SPSecureStoreServiceApp]SecureStoreServiceApp')
        }

        SPSearchServiceApp SearchServiceApp
        {  
            Name                  = "Search Service Application"
            DatabaseName          = '${GenerateUsernames.db}_Search'
            ApplicationPool       = $serviceAppPoolName
            PsDscRunAsCredential  = $SPSetupAccount
            DependsOn             = "[SPServiceAppPool]MainServiceAppPool"
        }

        SPSearchTopology SearchTopology
        {
            ServiceAppName          = "Search Service Application"
            Admin                   = '{tag:Name}'
            Crawler                 = '{tag:Name}'
            ContentProcessing       = '{tag:Name}'
            AnalyticsProcessing     = '{tag:Name}'
            QueryProcessing         = '{tag:Name}'
            IndexPartition          = '{tag:Name}'
            FirstPartitionDirectory = "D:\search"
            PsDscRunAsCredential    = $SPSetupAccount
            DependsOn               = "[SPSearchServiceApp]SearchServiceApp"
        }

        Script SignalCFN {
            DependsOn = @(
                "[SPSearchTopology]SearchTopology"
            )
            GetScript = { return @{} }
            TestScript = {
                $value = Get-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                if ($null -eq $value) { return $false }
                if ($value.SignalSent -eq $true) { return $true }
                return $false
            }
            SetScript = {
                Start-Process -FilePath "cfn-signal.exe" -ArgumentList @("-s", "true", (Get-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart).SignalUrl) -PassThru -Wait
                New-Item -Path HKLM:\SOFTWARE\Amazon\QuickStart -ErrorAction SilentlyContinue
                Set-ItemProperty -Path HKLM:\SOFTWARE\Amazon\QuickStart -Name SignalSent -Value $true
            }
        }
    }
}

SharePointServer -OutputPath .\MOF -ConfigurationData @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowPlainTextPassword = $true
        }
    )
}x

# Trim content we dont need from the MOF so it can be copied in to CFN
$mof = Get-Content "${PSScriptRoot}\MOF\localhost.mof" | Where-Object -FilterScript { 
    $_ -notlike "*SourceInfo = *" -and `
    $_ -notlike "*Author=`"*" -and `
    $_ -notlike "*GenerationDate=`"*" -and `
    $_ -notlike "*GenerationHost=`"*" -and `
    $_ -ne '/*' -and `
    $_ -ne '*/' -and `
    $_ -notlike '@TargetNode=*' -and `
    $_ -notlike '@GeneratedBy=*' -and `
    $_ -notlike '@GenerationDate=*' -and `
    $_ -notlike '@GenerationHost=*' 
} | Where-Object -FilterScript { 
    [String]::IsNullOrEmpty($_.Trim()) -eq $false
} | ForEach-Object -Process {
    return "        $_"
}
    
$mof | Out-File -FilePath "${PSScriptRoot}\MOF\localhost.mof" -Force
