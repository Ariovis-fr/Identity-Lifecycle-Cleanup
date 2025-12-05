# ========================================
# Report Service
# ========================================

function Export-InactiveUsersReport {
    <#
    .SYNOPSIS
    Generates inactive users report

    .PARAMETER Users
    Collection of inactive users (merged AD + Entra)

    .PARAMETER OutputPath
    Output file path

    .PARAMETER Format
    Output format: Text

    .EXAMPLE
    Export-InactiveUsersReport -Users $users -OutputPath "report.txt" -Format Text
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Users,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [ValidateSet('Text')]
        [string]$Format = 'Text'

    )


    switch ($Format) {
        'Text' {
            Export-TextReport -Users $Users -OutputPath $OutputPath
        }
    }

}

function Export-TextReport {
    <#
    .SYNOPSIS
    Generates text format report

    .PARAMETER Users
    Users

    .PARAMETER OutputPath
    Output file
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Users,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $content = @"
========================================
INACTIVE USERS - DUAL SYSTEM
Active Directory AND Entra ID
========================================

Generated on: $((Get-Date).ToUniversalTime().ToString("dd/MM/yyyy HH:mm:ss")) UTC
Total count: $($Users.Count) user(s)

"@

    foreach ($user in ($Users | Sort-Object DaysSinceActivity -Descending)) {
        $dateStr = if ($user.LastActivityDate) {
            "$($user.LastActivityDate.ToString("dd/MM/yyyy HH:mm:ss")) UTC"
        } else {
            "Never logged in"
        }

        $daysSince = if ($user.DaysSinceActivity) {
            "$($user.DaysSinceActivity) days"
        } else {
            "N/A"
        }

        $content += @"
----------------------------------------
User             : $($user.Name)
SamAccountName   : $($user.SamAccountName)
UPN              : $($user.UPN)
Email            : $(if ($user.Mail) { $user.Mail } else { "N/A" })
Status           : $(if ($user.Enabled) { "Enabled" } else { "Disabled" })

Last activity    : $dateStr (source: $($user.LastActivitySource))
Days inactive    : $daysSince

Details:
  - AD Last Logon        : $(if ($user.ADLastLogon) { "$($user.ADLastLogon.ToString("dd/MM/yyyy HH:mm:ss")) UTC" } else { "Never logged in via Active Directory" })
  - Entra ID Last SignIn : $(if ($user.EntraLastSignIn) { "$($user.EntraLastSignIn.ToString("dd/MM/yyyy HH:mm:ss")) UTC" } else { "Never logged in via Entra ID" })
  - Manager              : $(if ($user.Manager) { $user.Manager } else { "N/A" })

"@
    }

    $content | Out-File -FilePath $OutputPath -Encoding UTF8

    return $OutputPath
}

Export-ModuleMember -Function Export-InactiveUsersReport, Export-TextReport
