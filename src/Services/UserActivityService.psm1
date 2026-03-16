# ========================================
# User Activity Service
# Business logic for user activity comparison and analysis
# ========================================

function Compare-InactiveUsers {
    <#
    .SYNOPSIS
    Identifies all truly inactive users across AD and Entra ID

    .DESCRIPTION
    Cross-references inactive users from both systems with full identity lists
    to determine who is truly inactive in the enterprise:
    - Inactive in both systems → inactive
    - Inactive in AD, does not exist in Entra → inactive
    - Inactive in Entra, does not exist in AD → inactive
    - Inactive in AD, but active in Entra → ACTIVE (excluded)
    - Inactive in Entra, but active in AD → ACTIVE (excluded)

    .PARAMETER ADUsers
    Collection of inactive AD users (from Get-InactiveADUsers)

    .PARAMETER EntraIdUsers
    Collection of inactive Entra ID users (from Get-InactiveEntraIdUsers)

    .PARAMETER AllADIdentities
    List of all AD SamAccountNames (lowercase). Used to check if an Entra-only
    inactive user exists in AD. If not provided, all Entra-only users are included.

    .PARAMETER AllEntraIdentities
    List of all Entra UPN prefixes (lowercase). Used to check if an AD-only
    inactive user exists in Entra. If not provided, all AD-only users are included.

    .PARAMETER MatchingStrategy
    Matching strategy: 'SamAccountName' (default), 'Mail', 'UPN'
    #>

    [CmdletBinding()]
    param(
        [object[]]$ADUsers = @(),

        [object[]]$EntraIdUsers = @(),

        [string[]]$AllADIdentities,

        [string[]]$AllEntraIdentities,

        [ValidateSet('SamAccountName', 'Mail', 'UPN')]
        [string]$MatchingStrategy = 'SamAccountName'
    )

    # Build lookup dictionaries for inactive users
    $entraDict = @{}
    foreach ($entraUser in $EntraIdUsers) {
        $key = Get-UserMatchKey -User $entraUser -Source "Entra" -Strategy $MatchingStrategy
        if ($key) { $entraDict[$key] = $entraUser }
    }

    $adDict = @{}
    foreach ($adUser in $ADUsers) {
        $key = Get-UserMatchKey -User $adUser -Source "AD" -Strategy $MatchingStrategy
        if ($key) { $adDict[$key] = $adUser }
    }

    # Build lookup sets for all identities (for existence checks)
    $allEntraSet = @{}
    if ($AllEntraIdentities) {
        foreach ($id in $AllEntraIdentities) { $allEntraSet[$id] = $true }
    }

    $allADSet = @{}
    if ($AllADIdentities) {
        foreach ($id in $AllADIdentities) { $allADSet[$id] = $true }
    }

    $results = @()
    $processedKeys = @{}

    # --- Pass 1: AD inactive users ---
    foreach ($adUser in $ADUsers) {
        $key = Get-UserMatchKey -User $adUser -Source "AD" -Strategy $MatchingStrategy
        if (-not $key) { continue }

        $processedKeys[$key] = $true

        if ($entraDict.ContainsKey($key)) {
            # Inactive in both systems → truly inactive
            $results += Merge-UserActivityData -ADUser $adUser -EntraUser $entraDict[$key]
        }
        elseif ($AllEntraIdentities -and $allEntraSet.ContainsKey($key)) {
            # Exists in Entra but not in inactive list → active in Entra → skip
            Write-Verbose "  $key : inactive in AD but active in Entra → skipped"
        }
        else {
            # Does not exist in Entra (or no Entra identity list provided) → AD-only inactive
            $results += New-SingleSourceActivity -User $adUser -Source "AD"
        }
    }

    # --- Pass 2: Entra inactive users not yet processed ---
    foreach ($entraUser in $EntraIdUsers) {
        $key = Get-UserMatchKey -User $entraUser -Source "Entra" -Strategy $MatchingStrategy
        if (-not $key -or $processedKeys.ContainsKey($key)) { continue }

        if ($AllADIdentities -and $allADSet.ContainsKey($key)) {
            # Exists in AD but not in inactive list → active in AD → skip
            Write-Verbose "  $key : inactive in Entra but active in AD → skipped"
        }
        else {
            # Does not exist in AD (or no AD identity list provided) → Entra-only inactive
            $results += New-SingleSourceActivity -User $entraUser -Source "Entra"
        }
    }

    return , $results
}

function Get-UserMatchKey {
    <#
    .SYNOPSIS
    Extracts a matching key from a user object based on the strategy
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,

        [Parameter(Mandatory)]
        [ValidateSet("AD", "Entra")]
        [string]$Source,

        [string]$Strategy = "SamAccountName"
    )

    switch ($Strategy) {
        'SamAccountName' {
            if ($Source -eq "AD") {
                $User.SamAccountName.ToLower()
            } else {
                if ($User.UserPrincipalName -match '^([^@]+)@') {
                    $matches[1].ToLower()
                } else {
                    $User.UserPrincipalName.ToLower()
                }
            }
        }
        'Mail' {
            if ($User.Mail) { $User.Mail.ToLower() } else { $null }
        }
        'UPN' {
            if ($Source -eq "AD") {
                $User.SamAccountName.ToLower()
            } else {
                $User.UserPrincipalName.ToLower()
            }
        }
    }
}

function New-SingleSourceActivity {
    <#
    .SYNOPSIS
    Creates a standardized activity object for a user present in only one system
    #>
    param(
        [Parameter(Mandatory)]
        [object]$User,

        [Parameter(Mandatory)]
        [ValidateSet("AD", "Entra")]
        [string]$Source
    )

    if ($Source -eq "AD") {
        $lastDate = $User.LastLogon
        $daysSince = if ($lastDate) {
            (New-TimeSpan -Start $lastDate -End (Get-Date).ToUniversalTime()).Days
        } else { $null }

        return [PSCustomObject]@{
            SamAccountName     = $User.SamAccountName
            Name               = $User.Name
            UPN                = $null
            Mail               = $User.Mail
            Enabled            = $User.Enabled
            LastActivityDate   = $lastDate
            LastActivitySource = if ($lastDate) { "Active Directory" } else { "" }
            ADLastLogon        = $lastDate
            EntraLastSignIn    = $null
            DaysSinceActivity  = $daysSince
            ADCreatedDate      = $User.WhenCreated
            EntraCreatedDate   = $null
            Manager            = $User.Manager
        }
    }
    else {
        $lastDate = $User.LastSignIn
        $daysSince = if ($lastDate) {
            (New-TimeSpan -Start $lastDate -End (Get-Date).ToUniversalTime()).Days
        } else { $null }

        $sam = if ($User.UserPrincipalName -match '^([^@]+)@') {
            $matches[1]
        } else { $User.UserPrincipalName }

        return [PSCustomObject]@{
            SamAccountName     = $sam
            Name               = $User.DisplayName
            UPN                = $User.UserPrincipalName
            Mail               = $User.Mail
            Enabled            = $null
            LastActivityDate   = $lastDate
            LastActivitySource = if ($lastDate) { "Entra ID" } else { "" }
            ADLastLogon        = $null
            EntraLastSignIn    = $lastDate
            DaysSinceActivity  = $daysSince
            ADCreatedDate      = $null
            EntraCreatedDate   = $User.CreatedDateTime
            Manager            = $null
        }
    }
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


Export-ModuleMember -Function Compare-InactiveUsers, Merge-UserActivityData, New-SingleSourceActivity, Get-UserMatchKey
