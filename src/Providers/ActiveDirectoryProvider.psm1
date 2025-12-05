# ========================================
# Active Directory Provider
# ========================================

function Get-InactiveADUsers {
    <#
    .SYNOPSIS
    Retrieves inactive AD users

    .DESCRIPTION
    Queries Active Directory to get users inactive for X days

    .PARAMETER InactiveDays
    Number of days of inactivity

    .PARAMETER Server
    AD server to query

    .PARAMETER Credential
    Credentials for AD connection

    .PARAMETER SearchBase
    OU Distinguished Name to search in (e.g., "OU=People,DC=SD,DC=DIKA,DC=BE")
    If not specified, searches entire domain

    .EXAMPLE
    $users = Get-InactiveADUsers -InactiveDays 90 -Server "dc.example.com" -Credential $cred

    .EXAMPLE
    $users = Get-InactiveADUsers -InactiveDays 90 -Server "dc.example.com" -Credential $cred -SearchBase "OU=People,DC=SD,DC=DIKA,DC=BE"
    #>

    [CmdletBinding()]
    param(
        [int]$InactiveDays = 75,

        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [string]$SearchBase
    )

    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        # Build the filter
        $filter = { Enabled -eq $true }

        # Prepare Get-ADUser parameters
        $adParams = @{
            Filter     = $filter
            Server     = $Server
            Credential = $Credential
            Properties = @('LastLogon', 'LastLogonDate', 'mail', 'Manager', 'Enabled', 'WhenCreated')
        }

        # Add SearchBase if specified (to target specific OU like People)
        if ($SearchBase) {
            $adParams['SearchBase'] = $SearchBase
        }

        # Retrieve all users with necessary properties
        $allUsers = Get-ADUser @adParams

        # Calculate cutoff date in UTC
        $cutoffDate = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)

        # Filter inactive users
        $inactiveUsers = $allUsers | Where-Object {
            $lastLogonDate = Get-ADUserLastLogonDate -User $_

            if ($lastLogonDate) {
                $lastLogonDate -lt $cutoffDate
            } else {
                # Include never-logged users if created more than InactiveDays ago
                if ($_.WhenCreated) {
                    $_.WhenCreated -lt $cutoffDate
                } else {
                    $false # Exclude users with neither last logon nor when created
                }
            }
        }

        # Map to standardized format
        $results = $inactiveUsers | ForEach-Object {
            $lastLogonDate = Get-ADUserLastLogonDate -User $_
            $daysSinceLogon = if ($lastLogonDate) {
                (New-TimeSpan -Start $lastLogonDate -End (Get-Date).ToUniversalTime()).Days
            } else {
                $null
            }

            [PSCustomObject]@{
                SamAccountName   = $_.SamAccountName
                Name             = $_.Name
                Enabled          = $_.Enabled
                LastLogon        = $lastLogonDate
                DaysSinceLogon   = $daysSinceLogon
                Mail             = $_.mail
                Manager          = $_.Manager
                WhenCreated      = $_.WhenCreated
                DistinguishedName = $_.DistinguishedName
            }
        }

        return $results

    } catch {
        throw "Error retrieving AD users: $_"
    }
}

function Get-ADUserLastLogonDate {
    <#
    .SYNOPSIS
    Calculates AD user's last logon date in UTC

    .DESCRIPTION
    Uses LastLogonDate if available, otherwise converts LastLogon from FileTime
    ALWAYS returns dates in UTC timezone for consistency

    .PARAMETER User
    AD user object

    .EXAMPLE
    $date = Get-ADUserLastLogonDate -User $adUser
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$User
    )

    # LastLogonDate is more reliable (replicated)
    if ($User.LastLogonDate) {
        # Convert to UTC if it's a local datetime
        return $User.LastLogonDate.ToUniversalTime()
    }

    return $null
}

function Get-ADCredentialFromConfig {
    <#
    .SYNOPSIS
    Creates a PSCredential object from configuration

    .PARAMETER Username
    AD username

    .PARAMETER Password
    Plain text password

    .EXAMPLE
    $cred = Get-ADCredentialFromConfig -Username "domain\admin" -Password "secret"
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($Username, $securePassword)
}

Export-ModuleMember -Function Get-InactiveADUsers, Get-ADUserLastLogonDate, Get-ADCredentialFromConfig
