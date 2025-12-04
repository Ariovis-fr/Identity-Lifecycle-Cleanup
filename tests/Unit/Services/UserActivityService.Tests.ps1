# Exemple : Invoke-Pester .\tests\Unit\Services\UserActivityService.Tests.ps1

# Importer le module à tester
 Import-Module "$PSScriptRoot\..\..\..\src\Services\UserActivityService.psm1" -Force

Describe "Merge-UserActivityData" {

    It "Devrait choisir la date AD si elle est plus récente" {
        # Arrange - Créer des objets utilisateurs fictifs
        $adUser = [PSCustomObject]@{
            SamAccountName = "jdupont"
            Name = "Jean Dupont"
            Enabled = $true
            LastLogon = [DateTime]"2025-12-01 10:00:00"
            Mail = "jdupont@example.com"
            Manager = "CN=Manager,DC=example,DC=com"
            WhenCreated = [DateTime]"2020-01-01"
        }

        $entraUser = [PSCustomObject]@{
            UserPrincipalName = "jdupont@example.com"
            DisplayName = "Jean Dupont"
            LastSignIn = [DateTime]"2025-11-20 08:00:00"
            Mail = "jdupont@example.com"
            CreatedDateTime = [DateTime]"2020-01-01"
        }

        # Act - Appeler la fonction
        $result = Merge-UserActivityData -ADUser $adUser -EntraUser $entraUser

        # Assert - Vérifier le résultat
        $result.LastActivityDate | Should Be $adUser.LastLogon
        $result.LastActivitySource | Should Be "Active Directory"
    }
}
