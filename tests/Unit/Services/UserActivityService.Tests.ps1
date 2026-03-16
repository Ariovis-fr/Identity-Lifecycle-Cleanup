# ========================================
# Tests unitaires — UserActivityService
# ========================================
# Invoke-Pester .\tests\Unit\Services\UserActivityService.Tests.ps1 -Output Detailed

Import-Module "$PSScriptRoot\..\..\..\src\Services\UserActivityService.psm1" -Force

BeforeAll {

    function New-FakeADUser {
        param(
            [string]$SamAccountName = "jdupont",
            [string]$Name           = "Jean Dupont",
            [bool]$Enabled          = $true,
            $LastLogon              = ([DateTime]"2025-06-15 10:00:00"),
            [string]$Mail           = "jdupont@example.com",
            [string]$Manager        = "CN=Chef,OU=Managers,DC=example,DC=com",
            [DateTime]$WhenCreated  = ([DateTime]"2020-01-15")
        )
        return [PSCustomObject]@{
            SamAccountName = $SamAccountName
            Name           = $Name
            Enabled        = $Enabled
            LastLogon      = $LastLogon
            Mail           = $Mail
            Manager        = $Manager
            WhenCreated    = $WhenCreated
        }
    }

    function New-FakeEntraUser {
        param(
            [string]$UserPrincipalName = "jdupont@example.com",
            [string]$DisplayName       = "Jean Dupont",
            $LastSignIn                = ([DateTime]"2025-06-10 08:00:00"),
            [string]$Mail              = "jdupont@example.com",
            [DateTime]$CreatedDateTime = ([DateTime]"2020-01-15")
        )
        return [PSCustomObject]@{
            UserPrincipalName = $UserPrincipalName
            DisplayName       = $DisplayName
            LastSignIn        = $LastSignIn
            Mail              = $Mail
            CreatedDateTime   = $CreatedDateTime
        }
    }
}

# ========================================
# Merge-UserActivityData
# ========================================

Describe "Merge-UserActivityData" {

    Context "Selection de la date la plus recente" {

        It "Choisit AD quand AD est plus recent que Entra" {
            $ad    = New-FakeADUser    -LastLogon  ([DateTime]"2025-12-01 10:00:00")
            $entra = New-FakeEntraUser -LastSignIn ([DateTime]"2025-11-20 08:00:00")

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.LastActivityDate   | Should -Be $ad.LastLogon
            $result.LastActivitySource | Should -Be "Active Directory"
        }

        It "Choisit Entra quand Entra est plus recent que AD" {
            $ad    = New-FakeADUser    -LastLogon  ([DateTime]"2025-10-01 10:00:00")
            $entra = New-FakeEntraUser -LastSignIn ([DateTime]"2025-12-15 14:00:00")

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.LastActivityDate   | Should -Be $entra.LastSignIn
            $result.LastActivitySource | Should -Be "Entra ID"
        }

        It "Choisit Entra quand les deux dates sont identiques" {
            $date  = [DateTime]"2025-11-01 12:00:00"
            $ad    = New-FakeADUser    -LastLogon  $date
            $entra = New-FakeEntraUser -LastSignIn $date

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.LastActivityDate   | Should -Be $date
            $result.LastActivitySource | Should -Be "Entra ID"
        }
    }

    Context "Un seul systeme a une date" {

        It "Choisit AD quand Entra est null" {
            $ad    = New-FakeADUser -LastLogon ([DateTime]"2025-09-01 10:00:00")
            $entra = New-FakeEntraUser -LastSignIn $null

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.LastActivityDate   | Should -Be $ad.LastLogon
            $result.LastActivitySource | Should -Be "Active Directory"
        }

        It "Choisit Entra quand AD est null" {
            $ad    = New-FakeADUser -LastLogon $null
            $entra = New-FakeEntraUser -LastSignIn ([DateTime]"2025-09-01 10:00:00")

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.LastActivityDate   | Should -Be $entra.LastSignIn
            $result.LastActivitySource | Should -Be "Entra ID"
        }
    }

    Context "Aucun systeme n'a de date" {

        It "Retourne null et chaine vide" {
            $ad    = New-FakeADUser    -LastLogon  $null
            $entra = New-FakeEntraUser -LastSignIn $null

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.LastActivityDate   | Should -BeNullOrEmpty
            $result.LastActivitySource | Should -Be ""
            $result.DaysSinceActivity  | Should -BeNullOrEmpty
        }
    }

    Context "Calcul de DaysSinceActivity" {

        It "Calcule correctement le nombre de jours" {
            $daysAgo  = 30
            $pastDate = (Get-Date).ToUniversalTime().AddDays(-$daysAgo)
            $ad       = New-FakeADUser -LastLogon $pastDate
            $entra    = New-FakeEntraUser -LastSignIn $null

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.DaysSinceActivity | Should -BeGreaterOrEqual ($daysAgo - 1)
            $result.DaysSinceActivity | Should -BeLessOrEqual    ($daysAgo + 1)
        }
    }

    Context "Format de sortie" {

        It "Contient toutes les proprietes attendues" {
            $result = Merge-UserActivityData -ADUser (New-FakeADUser) -EntraUser (New-FakeEntraUser)

            $expected = @(
                "SamAccountName", "Name", "UPN", "Mail", "Enabled",
                "LastActivityDate", "LastActivitySource",
                "ADLastLogon", "EntraLastSignIn", "DaysSinceActivity",
                "ADCreatedDate", "EntraCreatedDate", "Manager"
            )
            foreach ($prop in $expected) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It "Prend le mail AD en priorite" {
            $ad    = New-FakeADUser    -Mail "ad@corp.com"
            $entra = New-FakeEntraUser -Mail "entra@corp.com"

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.Mail | Should -Be "ad@corp.com"
        }

        It "Prend le mail Entra si AD est null" {
            $ad    = New-FakeADUser -Mail $null
            $entra = New-FakeEntraUser -Mail "entra@corp.com"

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.Mail | Should -Be "entra@corp.com"
        }

        It "Mappe correctement les champs AD et Entra" {
            $ad    = New-FakeADUser    -SamAccountName "amartin" -Name "Alice Martin"
            $entra = New-FakeEntraUser -UserPrincipalName "amartin@corp.com" -DisplayName "Alice Martin"

            $result = Merge-UserActivityData -ADUser $ad -EntraUser $entra

            $result.SamAccountName  | Should -Be "amartin"
            $result.Name            | Should -Be "Alice Martin"
            $result.UPN             | Should -Be "amartin@corp.com"
            $result.Enabled         | Should -Be $true
            $result.ADLastLogon     | Should -Be $ad.LastLogon
            $result.EntraLastSignIn | Should -Be $entra.LastSignIn
            $result.ADCreatedDate   | Should -Be $ad.WhenCreated
            $result.EntraCreatedDate| Should -Be $entra.CreatedDateTime
            $result.Manager         | Should -Be $ad.Manager
        }
    }
}

# ========================================
# New-SingleSourceActivity
# ========================================

Describe "New-SingleSourceActivity" {

    Context "Utilisateur AD uniquement" {

        It "Cree un objet avec les champs Entra a null" {
            $ad = New-FakeADUser -SamAccountName "adonly" -Name "AD Only User"

            $result = New-SingleSourceActivity -User $ad -Source "AD"

            $result.SamAccountName  | Should -Be "adonly"
            $result.Name            | Should -Be "AD Only User"
            $result.UPN             | Should -BeNullOrEmpty
            $result.EntraLastSignIn | Should -BeNullOrEmpty
            $result.EntraCreatedDate| Should -BeNullOrEmpty
            $result.ADLastLogon     | Should -Be $ad.LastLogon
            $result.LastActivitySource | Should -Be "Active Directory"
        }

        It "Gere un utilisateur AD sans LastLogon" {
            $ad = New-FakeADUser -LastLogon $null

            $result = New-SingleSourceActivity -User $ad -Source "AD"

            $result.LastActivityDate   | Should -BeNullOrEmpty
            $result.LastActivitySource | Should -Be ""
            $result.DaysSinceActivity  | Should -BeNullOrEmpty
        }
    }

    Context "Utilisateur Entra uniquement" {

        It "Cree un objet avec les champs AD a null" {
            $entra = New-FakeEntraUser -UserPrincipalName "entraonly@corp.com" -DisplayName "Entra Only"

            $result = New-SingleSourceActivity -User $entra -Source "Entra"

            $result.SamAccountName  | Should -Be "entraonly"
            $result.Name            | Should -Be "Entra Only"
            $result.UPN             | Should -Be "entraonly@corp.com"
            $result.ADLastLogon     | Should -BeNullOrEmpty
            $result.ADCreatedDate   | Should -BeNullOrEmpty
            $result.EntraLastSignIn | Should -Be $entra.LastSignIn
            $result.LastActivitySource | Should -Be "Entra ID"
        }

        It "Gere un utilisateur Entra sans LastSignIn" {
            $entra = New-FakeEntraUser -LastSignIn $null

            $result = New-SingleSourceActivity -User $entra -Source "Entra"

            $result.LastActivityDate   | Should -BeNullOrEmpty
            $result.LastActivitySource | Should -Be ""
            $result.DaysSinceActivity  | Should -BeNullOrEmpty
        }
    }

    Context "Format de sortie identique a Merge-UserActivityData" {

        It "Contient les memes proprietes que Merge-UserActivityData" {
            $merged = Merge-UserActivityData -ADUser (New-FakeADUser) -EntraUser (New-FakeEntraUser)
            $single = New-SingleSourceActivity -User (New-FakeADUser) -Source "AD"

            $mergedProps = $merged.PSObject.Properties.Name | Sort-Object
            $singleProps = $single.PSObject.Properties.Name | Sort-Object

            $singleProps | Should -Be $mergedProps
        }
    }
}

# ========================================
# Compare-InactiveUsers
# ========================================

Describe "Compare-InactiveUsers" {

    Context "Utilisateurs inactifs dans les deux systemes" {

        It "Retourne un utilisateur inactif dans les deux systemes" {
            $ad    = @( New-FakeADUser -SamAccountName "jdupont" )
            $entra = @( New-FakeEntraUser -UserPrincipalName "jdupont@example.com" )

            $result = Compare-InactiveUsers -ADUsers $ad -EntraIdUsers $entra

            $result.Count | Should -Be 1
            $result[0].SamAccountName | Should -Be "jdupont"
        }

        It "Match en case-insensitive" {
            $ad    = @( New-FakeADUser -SamAccountName "JDupont" )
            $entra = @( New-FakeEntraUser -UserPrincipalName "jdupont@example.com" )

            $result = Compare-InactiveUsers -ADUsers $ad -EntraIdUsers $entra

            $result.Count | Should -Be 1
        }
    }

    Context "Utilisateur inactif dans un seul systeme, absent de l'autre" {

        It "Inclut un utilisateur AD-only quand il n'existe PAS dans Entra" {
            $ad    = @( New-FakeADUser -SamAccountName "adonly" )
            $entra = @()
            $allEntra = @("autreuser")  # adonly n'est pas dans Entra

            $result = Compare-InactiveUsers -ADUsers $ad -EntraIdUsers $entra -AllEntraIdentities $allEntra

            $result.Count | Should -Be 1
            $result[0].SamAccountName | Should -Be "adonly"
        }

        It "Inclut un utilisateur Entra-only quand il n'existe PAS dans AD" {
            $ad    = @()
            $entra = @( New-FakeEntraUser -UserPrincipalName "entraonly@corp.com" )
            $allAD = @("autreuser")  # entraonly n'est pas dans AD

            $result = Compare-InactiveUsers -EntraIdUsers $entra -AllADIdentities $allAD

            $result.Count | Should -Be 1
            $result[0].SamAccountName | Should -Be "entraonly"
        }
    }

    Context "Utilisateur inactif dans un systeme, ACTIF dans l'autre" {

        It "Exclut un utilisateur inactif AD qui est actif dans Entra" {
            $ad    = @( New-FakeADUser -SamAccountName "jdupont" )
            $entra = @()  # pas dans la liste des inactifs Entra
            $allEntra = @("jdupont")  # mais existe dans Entra → donc actif

            $result = Compare-InactiveUsers -ADUsers $ad -EntraIdUsers $entra -AllEntraIdentities $allEntra

            $result.Count | Should -Be 0
        }

        It "Exclut un utilisateur inactif Entra qui est actif dans AD" {
            $ad    = @()  # pas dans la liste des inactifs AD
            $entra = @( New-FakeEntraUser -UserPrincipalName "jdupont@corp.com" )
            $allAD = @("jdupont")  # existe dans AD → donc actif

            $result = Compare-InactiveUsers -EntraIdUsers $entra -AllADIdentities $allAD

            $result.Count | Should -Be 0
        }
    }

    Context "Client avec un seul systeme (pas de liste d'identites)" {

        It "Inclut tous les inactifs AD quand pas de liste Entra" {
            $ad = @(
                New-FakeADUser -SamAccountName "user1" -Name "User 1" -Mail "u1@corp.com"
                New-FakeADUser -SamAccountName "user2" -Name "User 2" -Mail "u2@corp.com"
            )

            $result = Compare-InactiveUsers -ADUsers $ad

            $result.Count | Should -Be 2
        }

        It "Inclut tous les inactifs Entra quand pas de liste AD" {
            $entra = @(
                New-FakeEntraUser -UserPrincipalName "user1@corp.com" -DisplayName "User 1"
                New-FakeEntraUser -UserPrincipalName "user2@corp.com" -DisplayName "User 2"
            )

            $result = Compare-InactiveUsers -EntraIdUsers $entra

            $result.Count | Should -Be 2
        }
    }

    Context "Scenario complet multi-utilisateurs" {

        It "Traite correctement un mix de tous les cas" {
            $ad = @(
                New-FakeADUser -SamAccountName "both"    -Name "Both Inactive"  -Mail "both@corp.com"
                New-FakeADUser -SamAccountName "adonly"   -Name "AD Only"        -Mail "adonly@corp.com"
                New-FakeADUser -SamAccountName "adactive" -Name "AD Inact Entra Act" -Mail "adactive@corp.com"
            )
            $entra = @(
                New-FakeEntraUser -UserPrincipalName "both@corp.com"      -DisplayName "Both Inactive"
                New-FakeEntraUser -UserPrincipalName "entraonly@corp.com" -DisplayName "Entra Only"
                New-FakeEntraUser -UserPrincipalName "entractive@corp.com" -DisplayName "Entra Inact AD Act"
            )
            $allEntra = @("both", "adactive", "entraonly", "entractive", "someactiveuser")
            $allAD    = @("both", "adonly", "adactive", "entractive", "someotheractive")

            $result = Compare-InactiveUsers `
                -ADUsers $ad `
                -EntraIdUsers $entra `
                -AllEntraIdentities $allEntra `
                -AllADIdentities $allAD

            # both     → inactif AD + inactif Entra → INCLUS
            # adonly   → inactif AD + n'existe pas Entra → INCLUS
            # adactive → inactif AD + actif Entra (dans allEntra mais pas dans $entra) → EXCLU
            # entraonly → inactif Entra + n'existe pas AD → INCLUS
            # entractive → inactif Entra + actif AD (dans allAD mais pas dans $ad inactifs) → EXCLU

            $result.Count | Should -Be 3
            $result.SamAccountName | Should -Contain "both"
            $result.SamAccountName | Should -Contain "adonly"
            $result.SamAccountName | Should -Contain "entraonly"
            $result.SamAccountName | Should -Not -Contain "adactive"
            $result.SamAccountName | Should -Not -Contain "entractive"
        }
    }

    Context "Matching par Mail" {

        It "Match par adresse email" {
            $ad    = @( New-FakeADUser -SamAccountName "jdupont" -Mail "jean.dupont@corp.com" )
            $entra = @( New-FakeEntraUser -UserPrincipalName "jdupont@corp.com" -Mail "jean.dupont@corp.com" )

            $result = Compare-InactiveUsers -ADUsers $ad -EntraIdUsers $entra -MatchingStrategy "Mail"

            $result.Count | Should -Be 1
        }

        It "Ignore les utilisateurs sans mail" {
            $adUser = New-FakeADUser
            $adUser.Mail = $null

            $result = Compare-InactiveUsers -ADUsers @($adUser) -EntraIdUsers @(New-FakeEntraUser) -MatchingStrategy "Mail"

            # AD user has no mail → key is null → cannot be matched or included
            # Only the Entra user (who has a mail) is included as Entra-only
            $result.Count | Should -Be 1
        }
    }

    Context "Tableau vide" {

        It "Retourne un tableau vide si aucune donnee" {
            $result = Compare-InactiveUsers

            $result.Count | Should -Be 0
        }
    }
}
