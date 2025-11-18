# Script to populate the ADUserLogon table with AD data
 
param(
    [Parameter(Mandatory = $false)]
    [string]$ADConnection = "MY_AD"
)
 
# Import Environment module
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "..\Environment.psm1") -Force
Write-Host "Configuration loaded from appsettings.agent.json" -ForegroundColor Green
 
# Import-Module ActiveDirectory
Import-Module ActiveDirectory
 
# Database configuration
$SqlServer = "INSERT YOUR INFORMATION"
$Database = "INSERT YOUR INFORMATION"
$Table = "INSERT YOUR INFORMATION"
$SqlUser = "INSERT YOUR INFORMATION"
$SqlPassword = "INSERT YOUR INFORMATION"
 
# Retrieve AD configuration
$adConfig = $UsercubeSession.Connections.$ADConnection
$ServerWithPort = $adConfig.Servers[0].Server
# Extract server name without port for ActiveDirectory module
$DomainController = $ServerWithPort.Split(':')[0]
 
Write-Host "=== Configuration ===" -ForegroundColor Cyan
Write-Host "AD Server: $DomainController" -ForegroundColor Green
Write-Host "AD Login: $($adConfig.Login)" -ForegroundColor Green
Write-Host "SQL Server: $SqlServer" -ForegroundColor Green
Write-Host "Database: $Database" -ForegroundColor Green
Write-Host "SQL User: $SqlUser" -ForegroundColor Green
Write-Host
 
# Create AD credentials
$securePassword = ConvertTo-SecureString $adConfig.Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($adConfig.Login, $securePassword)
 
# SQL Connection
$connectionString = "Server=$SqlServer;Database=$Database;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True;Connection Timeout=30;"
 
try {
    Write-Host "=== Connexion a la base de donnees ===" -ForegroundColor Cyan
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $SqlConnection.Open()
    Write-Host "SQL connection successful" -ForegroundColor Green
   
    # Clear the table to avoid duplicates (use DELETE instead of TRUNCATE)
    Write-Host
    Write-Host "=== Nettoyage de la table ===" -ForegroundColor Cyan
    $deleteCommand = $SqlConnection.CreateCommand()
    $deleteCommand.CommandText = "DELETE FROM $Table"
    $rowsDeleted = $deleteCommand.ExecuteNonQuery()
    Write-Host "$rowsDeleted records deleted" -ForegroundColor Green
   
    # Retrieve AD users
    Write-Host
    Write-Host "=== Retrieving AD users ===" -ForegroundColor Cyan
   
    # Retrieve only ACTIVE users (Enabled = true)
    $Users = Get-ADUser -Filter {Enabled -eq $true} -Server $DomainController -Credential $cred -Properties SamAccountName, LastLogon, Name, UserPrincipalName, Enabled
   
    # Limit to 30 users for testing
    $Users = $Users | Select-Object -First 30
   
    Write-Host "$($Users.Count) ACTIVE users retrieved (limited to 30 for testing)" -ForegroundColor Green
    Write-Host
   
    # Processing and insertion
    Write-Host "=== Database insertion ===" -ForegroundColor Cyan
   
    $insertCount = 0
    $errorCount = 0
   
    foreach ($User in $Users) {
        try {
            # Convert lastLogon to DateTime (or null if never logged in)
            if ($User.LastLogon -ne 0 -and $User.LastLogon -ne $null) {
                $LastLogonDate = [DateTime]::FromFileTime($User.LastLogon)
                $DaysSinceLastLogon = (New-TimeSpan -Start $LastLogonDate -End (Get-Date)).Days
            } else {
                $LastLogonDate = $null
                $DaysSinceLastLogon = $null
            }
           
            # Status always "Enabled" since we only retrieve active accounts
            $Status = "Enabled"
           
            # For now, these fields are NULL (to be filled later)
            $Mail = $null
            $MailManager = $null
           
            # Default relance flags to false (0)
            $Relance1 = 0
            $Relance2 = 0
           
            # Insert into SQL
            $SqlCommand = $SqlConnection.CreateCommand()
            $SqlCommand.CommandText = @"
                INSERT INTO $Table (
                    SamAccountName, Name, Status, LastLogon, Days, Mail, MailManager, Relance1, Relance2
                ) VALUES (
                    @sam, @name, @status, @logon, @days, @mail, @managerMail, @rel1, @rel2
                )
"@
            $SqlCommand.Parameters.AddWithValue("@sam", $User.SamAccountName) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@name", $User.Name) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@status", $Status) | Out-Null
           
            if ($LastLogonDate -eq $null) {
                $SqlCommand.Parameters.AddWithValue("@logon", [DBNull]::Value) | Out-Null
            } else {
                $SqlCommand.Parameters.AddWithValue("@logon", $LastLogonDate) | Out-Null
            }
           
            if ($DaysSinceLastLogon -eq $null) {
                $SqlCommand.Parameters.AddWithValue("@days", [DBNull]::Value) | Out-Null
            } else {
                $SqlCommand.Parameters.AddWithValue("@days", $DaysSinceLastLogon) | Out-Null
            }
           
            $SqlCommand.Parameters.AddWithValue("@mail", [DBNull]::Value) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@managerMail", [DBNull]::Value) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@rel1", $Relance1) | Out-Null
            $SqlCommand.Parameters.AddWithValue("@rel2", $Relance2) | Out-Null
           
            $SqlCommand.ExecuteNonQuery()
            $insertCount++
           
            # Display progress every 100 users
            if ($insertCount % 100 -eq 0) {
                Write-Host "Processed $insertCount/$($Users.Count) users..." -ForegroundColor Yellow
            }
        }
        catch {
            $errorCount++
            Write-Warning "Error inserting $($User.SamAccountName): $($_.Exception.Message)"
        }
    }
   
    Write-Host
    Write-Host "=== Results ===" -ForegroundColor Cyan
    Write-Host "$insertCount users successfully inserted" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Host "$errorCount errors encountered" -ForegroundColor Yellow
    }
   
    # Verify inserted data
    $countCommand = $SqlConnection.CreateCommand()
    $countCommand.CommandText = "SELECT COUNT(*) FROM $Table"
    $totalRecords = $countCommand.ExecuteScalar()
   
    Write-Host "Total records in table: $totalRecords" -ForegroundColor Cyan
   
    # Process inactive accounts > 90 days
    Write-Host
    Write-Host "=== Processing inactive accounts > 90 days ===" -ForegroundColor Yellow
   
    $inactiveUsersCommand = $SqlConnection.CreateCommand()
    $inactiveUsersCommand.CommandText = "SELECT SamAccountName, Name, Days FROM $Table WHERE Days > 90 ORDER BY Days DESC"
    $inactiveReader = $inactiveUsersCommand.ExecuteReader()
   
    $inactiveUsers = @()
    while ($inactiveReader.Read()) {
        $inactiveUsers += [PSCustomObject]@{
            SamAccountName = $inactiveReader['SamAccountName']
            Name = $inactiveReader['Name']
            Days = $inactiveReader['Days']
        }
    }
    $inactiveReader.Close()
   
    if ($inactiveUsers.Count -gt 0) {
        Write-Host "$($inactiveUsers.Count) inactive accounts > 90 days found" -ForegroundColor Red
       
        # Create Mails folder if it doesn't exist
        $mailsFolder = "C:\UsercubeAgent\Mails"
        if (!(Test-Path $mailsFolder)) {
            New-Item -ItemType Directory -Path $mailsFolder -Force | Out-Null
        }
       
        foreach ($inactiveUser in $inactiveUsers) {
            # Display in terminal
            Write-Host "call api + $($inactiveUser.SamAccountName)" -ForegroundColor Red
           
            # Create EML file to simulate email
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $emlFileName = "Desactivation_$($inactiveUser.SamAccountName)_$timestamp.eml"
            $emlPath = Join-Path $mailsFolder $emlFileName
           
            $emlContent = @"
From: no-reply@acme.com
To: it-admin@acme.com
Subject: [ALERT] AD Account Deactivation - $($inactiveUser.SamAccountName)
Date: $(Get-Date -Format 'ddd, dd MMM yyyy HH:mm:ss +0000')
Message-ID: <$([guid]::NewGuid())@acme.com>
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8
 
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #ff6b6b; color: white; padding: 15px; border-radius: 5px; }
        .content { background-color: #f8f9fa; padding: 20px; border-radius: 5px; margin-top: 10px; }
        .warning { background-color: #fff3cd; border: 1px solid #ffeaa7; padding: 10px; border-radius: 3px; margin: 10px 0; }
        .account-info { background-color: #ffffff; border: 1px solid #dee2e6; padding: 15px; border-radius: 5px; margin: 10px 0; }
        .footer { font-size: 12px; color: #6c757d; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="header">
        <h2>🚨 ALERT - Active Directory Account Deactivation</h2>
    </div>
   
    <div class="content">
        <p><strong>An inactive user account has been identified for automatic deactivation.</strong></p>
       
        <div class="account-info">
            <h3>📋 Account Information:</h3>
            <ul>
                <li><strong>Account Name:</strong> $($inactiveUser.SamAccountName)</li>
                <li><strong>Full Name:</strong> $($inactiveUser.Name)</li>
                <li><strong>Last Logon:</strong> $($inactiveUser.Days) days ago</li>
                <li><strong>Processing Date:</strong> $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</li>
            </ul>
        </div>
       
        <div class="warning">
            <h3>⚠️ Automated Actions Taken:</h3>
            <ul>
                <li>✅ Inactive account identified (> 90 days)</li>
                <li>🔄 API deactivation call scheduled</li>
                <li>📧 Notification sent to administrators</li>
                <li>📝 Entry added to audit logs</li>
            </ul>
        </div>
       
        <p><strong>Deactivation Criteria:</strong></p>
        <ul>
            <li>Active account in Active Directory</li>
            <li>No logon for more than 90 days</li>
            <li>Detected by automated audit process</li>
        </ul>
       
        <p><strong>Next Steps:</strong></p>
        <ol>
            <li>Manual verification if necessary</li>
            <li>Account deactivation in Active Directory</li>
            <li>User data archiving</li>
            <li>HR department notification</li>
        </ol>
    </div>
   
    <div class="footer">
        <p>This message was automatically generated by the Active Directory audit system.</p>
        <p>Process: Populate-ADUserLogon-DB-Clean.ps1</p>
        <p>Server: $env:COMPUTERNAME</p>
        <p>Timestamp: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>
    </div>
</body>
</html>
"@
           
            # Write EML file
            $emlContent | Out-File -FilePath $emlPath -Encoding UTF8
            Write-Host "  -> Email created: $emlFileName" -ForegroundColor Green
        }
       
        Write-Host
        Write-Host "Deactivation emails created in: $mailsFolder" -ForegroundColor Green
    }
    else {
        Write-Host "No inactive accounts > 90 days found" -ForegroundColor Green
    }
   
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($SqlConnection -and $SqlConnection.State -eq 'Open') {
        $SqlConnection.Close()
        Write-Host
        Write-Host "SQL connection closed." -ForegroundColor Gray
    }
}
 
Write-Host
Write-Host "=== Script completed ===" -ForegroundColor Cyan