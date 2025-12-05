# ========================================
# User Activity Service
# Business logic for user activity comparison and analysis
# ========================================

function Compare-InactiveUsers {
    <#
    .SYNOPSIS
    Compares inactive AD and Entra ID users

    .DESCRIPTION
    Identifies users present in BOTH systems as inactive

    .PARAMETER ADUsers
    Collection of inactive AD users

    .PARAMETER EntraIdUsers
    Collection of inactive Entra ID users

    .PARAMETER MatchingStrategy
    Matching strategy: 'SamAccountName' (default), 'Mail', 'UPN'

    .EXAMPLE
    $matched = Compare-InactiveUsers -ADUsers $adUsers -EntraIdUsers $entraUsers
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ADUsers,

        [Parameter(Mandatory)]
        [object[]]$EntraIdUsers,

        [ValidateSet('SamAccountName', 'Mail', 'UPN')]
        [string]$MatchingStrategy = 'SamAccountName'
    )

    # Create dictionaries for fast lookup
    $entraDict = @{}

    foreach ($entraUser in $EntraIdUsers) {
        $key = switch ($MatchingStrategy) {
            'SamAccountName' {
                # Extract part before @ from UPN
                if ($entraUser.UserPrincipalName -match '^([^@]+)@') {
                    $matches[1].ToLower()
                } else {
                    $entraUser.UserPrincipalName.ToLower()
                }
            }
            'Mail' {
                if ($entraUser.Mail) { $entraUser.Mail.ToLower() } else { $null }
            }
            'UPN' {
                $entraUser.UserPrincipalName.ToLower()
            }
        }

        if ($key) {
            $entraDict[$key] = $entraUser
        }
    }

    # Compare and match
    $matchedUsers = @()

    foreach ($adUser in $ADUsers) {
        $key = switch ($MatchingStrategy) {
            'SamAccountName' {
                $adUser.SamAccountName.ToLower()
            }
            'Mail' {
                if ($adUser.Mail) { $adUser.Mail.ToLower() } else { $null }
            }
            'UPN' {
                # Build potential UPN from SamAccountName
                $adUser.SamAccountName.ToLower()
            }
        }

        if ($key -and $entraDict.ContainsKey($key)) {
            $entraUser = $entraDict[$key]

            # Create combined object with last activity
            $mergedUser = Merge-UserActivityData -ADUser $adUser -EntraUser $entraUser

            $matchedUsers += $mergedUser
        }
    }

    return $matchedUsers
}

function Merge-UserActivityData {
    <#
    .SYNOPSIS
    Merges AD and Entra ID activity data

    .DESCRIPTION
    Determines actual last activity by comparing both sources

    .PARAMETER ADUser
    AD user

    .PARAMETER EntraUser
    Entra ID user

    .EXAMPLE
    $merged = Merge-UserActivityData -ADUser $adUser -EntraUser $entraUser
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ADUser,

        [Parameter(Mandatory)]
        [object]$EntraUser
    )

    $adDate = $ADUser.LastLogon
    $entraDate = $EntraUser.LastSignIn

    # Debug logs to see retrieved dates
    Write-Verbose "=== Merge-UserActivityData : $($ADUser.SamAccountName) ==="
    Write-Verbose "  AD Date        : $adDate"
    Write-Verbose "  Entra Date     : $entraDate"

    # Determine most recent date
    $lastActivityDate = $null
    $lastActivitySource = ""

    if ($adDate -and $entraDate) {
        if ($adDate -gt $entraDate) {
            $lastActivityDate = $adDate
            $lastActivitySource = "Active Directory"
            Write-Verbose "  → Selected: AD is more recent"
        } else {
            $lastActivityDate = $entraDate
            $lastActivitySource = "Entra ID"
            Write-Verbose "  → Selected: Entra ID is more recent (or equal)"
        }
    } elseif ($adDate) {
        $lastActivityDate = $adDate
        $lastActivitySource = "Active Directory"
        Write-Verbose "  → Selected: AD only (Entra is null)"
    } elseif ($entraDate) {
        $lastActivityDate = $entraDate
        $lastActivitySource = "Entra ID"
        Write-Verbose "  → Selected: Entra only (AD is null)"
    }

    # Calculate days since activity (using UTC for consistency)
    $daysSinceActivity = if ($lastActivityDate) {
        (New-TimeSpan -Start $lastActivityDate -End (Get-Date).ToUniversalTime()).Days
    } else {
        $null
    }

    Write-Verbose "  Final activity date        : $lastActivityDate"
    Write-Verbose "  Days since activity        : $daysSinceActivity"
    Write-Verbose "=== End Merge ==="

    return [PSCustomObject]@{
        SamAccountName      = $ADUser.SamAccountName
        Name                = $ADUser.Name
        UPN                 = $EntraUser.UserPrincipalName
        Mail                = if ($ADUser.Mail) { $ADUser.Mail } else { $EntraUser.Mail }
        Enabled             = $ADUser.Enabled
        LastActivityDate    = $lastActivityDate
        LastActivitySource  = $lastActivitySource
        ADLastLogon         = $adDate
        EntraLastSignIn     = $entraDate
        DaysSinceActivity   = $daysSinceActivity
        ADCreatedDate       = $ADUser.WhenCreated
        EntraCreatedDate    = $EntraUser.CreatedDateTime
        Manager             = $ADUser.Manager
    }
}


Export-ModuleMember -Function Compare-InactiveUsers, Merge-UserActivityData
