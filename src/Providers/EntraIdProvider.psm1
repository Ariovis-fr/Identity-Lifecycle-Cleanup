# ========================================
# Entra ID Provider
# ========================================

function Get-InactiveEntraIdUsers {
    <#
    Queries Microsoft Graph to get users inactive for X days

    PARAMETER
        InactiveDays : Number of days of inactivity (default: 75)
        TenantId : Azure tenant ID
        Clien ID
        ClientSecret : Application clitId : Azure applicationent secret
    #>

    [CmdletBinding()]
    param(
        [int]$InactiveDays = 75,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret
    )

    try {
        # Import Graph module
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            throw "Microsoft.Graph module not installed. Run: Install-Module Microsoft.Graph"
        }

        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        # Connect
        $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)

        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome

        # Calculate cutoff date in UTC
        $cutoffDate = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)

        # Retrieve all users with sign-in activity
        $allUsers = Get-MgUser -All -Property DisplayName, UserPrincipalName, SignInActivity, AccountEnabled, CreatedDateTime, Mail

        # Filter inactive users
        $inactiveUsers = $allUsers | Where-Object {
            $lastSignIn = Get-EntraUserLastSignInDate -User $_

            if ($lastSignIn) {
                $lastSignIn -lt $cutoffDate
            } else {
                # Include never-logged users if created more than InactiveDays ago
                if ($_.CreatedDateTime) {
                    $_.CreatedDateTime -lt $cutoffDate
                } else {
                    $true
                }
            }
        }

        # Map to standardized format
        $results = $inactiveUsers | ForEach-Object {
            $lastSignIn = Get-EntraUserLastSignInDate -User $_
            $daysSinceSignIn = if ($lastSignIn) {
                (New-TimeSpan -Start $lastSignIn -End (Get-Date).ToUniversalTime()).Days
            } else {
                $null
            }

            [PSCustomObject]@{
                DisplayName      = $_.DisplayName
                UserPrincipalName = $_.UserPrincipalName
                Mail             = $_.Mail
                LastSignIn       = $lastSignIn
                DaysSinceSignIn  = $daysSinceSignIn
                AccountEnabled   = $_.AccountEnabled
                CreatedDateTime  = $_.CreatedDateTime
            }
        }

        Disconnect-MgGraph | Out-Null

        return $results

    } catch {
        # In case of error, write the error but return empty array
        # to allow the main script to handle the error
        Write-Error "Error retrieving Entra ID users: $_"
        return @()
    }
}

function Get-EntraUserLastSignInDate {
    <#
    .SYNOPSIS
    Extracts Entra ID user's last sign-in date in UTC

    .DESCRIPTION
    Handles different possible formats of SignInActivity
    Microsoft Graph returns dates in UTC by default, but we ensure it

    .PARAMETER User
    Entra ID user object

    .EXAMPLE
    $date = Get-EntraUserLastSignInDate -User $entraUser
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$User
    )

    if (-not $User.SignInActivity) {
        return $null
    }

    $dateToReturn = $null

    # LastSignInDateTime is the most recent
    if ($User.SignInActivity.LastSignInDateTime) {
        $dateToReturn = $User.SignInActivity.LastSignInDateTime
    }
    # Fallback to LastNonInteractiveSignInDateTime
    elseif ($User.SignInActivity.LastNonInteractiveSignInDateTime) {
        $dateToReturn = $User.SignInActivity.LastNonInteractiveSignInDateTime
    }

    # Ensure UTC (Microsoft Graph should already return UTC, but this is a safety check)
    if ($dateToReturn -and $dateToReturn.Kind -ne [System.DateTimeKind]::Utc) {
        $dateToReturn = $dateToReturn.ToUniversalTime()
    }

    return $dateToReturn
}

function Connect-EntraIdFromConfig {
    <#
    .SYNOPSIS
    Connects to Entra ID from configuration

    .PARAMETER TenantId
    Tenant ID

    .PARAMETER ClientId
    Client ID

    .PARAMETER ClientSecret
    Client secret

    .EXAMPLE
    Connect-EntraIdFromConfig -TenantId "xxx" -ClientId "yyy" -ClientSecret "zzz"
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret
    )

    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureSecret)

    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
}

Export-ModuleMember -Function Get-InactiveEntraIdUsers, Get-EntraUserLastSignInDate, Connect-EntraIdFromConfig
