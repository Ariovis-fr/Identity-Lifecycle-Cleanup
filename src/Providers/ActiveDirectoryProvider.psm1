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
    OU Distinguished Name to search in (e.g., "OU=People,DC=EX,DC=EXAMPLE,DC=EN")
    If not specified, searches entire domain

    .EXAMPLE
    $users = Get-InactiveADUsers -InactiveDays 90 -Server "dc.example.com" -Credential $cred

    .EXAMPLE
    $users = Get-InactiveADUsers -InactiveDays 90 -Server "dc.example.com" -Credential $cred -SearchBase "OU=People,DC=EX,DC=EXAMPLE,DC=EN"
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
            Properties = @('LastLogon', 'mail', 'Manager', 'Enabled', 'WhenCreated')
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
            $lastLogon = Get-ADUserLastLogon -User $_

            if ($lastLogon) {
                # User has logged in before
                # Compare LastLogon (UTC) with cutoffDate (UTC)
                $lastLogon -lt $cutoffDate
            } else {
                # User never logged in
                # Check if account was created more than InactiveDays ago
                if ($_.WhenCreated) {
                    # Convert WhenCreated to UTC for comparison
                    $whenCreatedUTC = $_.WhenCreated.ToUniversalTime()
                    $whenCreatedUTC -lt $cutoffDate
                } else {
                    # No creation date - exclude this user (should not happen)
                    $false
                }
            }
        }

        # Map to standardized format
        $results = $inactiveUsers | ForEach-Object {
            $lastLogon = Get-ADUserLastLogon -User $_
            $daysSinceLogon = if ($lastLogon) {
                (New-TimeSpan -Start $lastLogon -End (Get-Date).ToUniversalTime()).Days
            } else {
                $null
            }

            [PSCustomObject]@{
                SamAccountName   = $_.SamAccountName
                Name             = $_.Name
                Enabled          = $_.Enabled
                LastLogon        = $lastLogon
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

function Get-ADUserLastLogon {
      <#
      .SYNOPSIS
      Converts AD LastLogon (FileTime) to DateTime UTC

      .DESCRIPTION
      Returns null if LastLogon = 0 (never logged in)
      Returns DateTime in UTC if LastLogon exists

      .PARAMETER User
      AD user object with LastLogon property

      .EXAMPLE
      $logon = Get-ADUserLastLogon -User $adUser
      # Returns: DateTime in UTC or $null
      #>

      [CmdletBinding()]
      param(
          [Parameter(Mandatory)]
          [object]$User
      )
     
      # LastLogon = 0 means "never logged in"
      if (-not $User.LastLogon -or $User.LastLogon -eq 0) {
          return $null
      }

      # Convert FileTime (Int64) to DateTime UTC
      try {
          return [DateTime]::FromFileTime($User.LastLogon)
      }
      catch {
          Write-Warning "Failed to convert LastLogon for $($User.SamAccountName): $_"
          return $null
      }
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

Export-ModuleMember -Function Get-InactiveADUsers, Get-ADUserLastLogon, Get-ADCredentialFromConfig
