# ========================================
# Tests unitaires — ActiveDirectoryProvider
# ========================================
# Invoke-Pester .\tests\Unit\Providers\ActiveDirectoryProvider.Tests.ps1 -Output Detailed

Import-Module "$PSScriptRoot\..\..\..\src\Providers\ActiveDirectoryProvider.psm1" -Force

# ========================================
# Get-ADUserLastLogon
# ========================================

Describe "Get-ADUserLastLogon" {

    Context "Conversion FileTime vers DateTime" {

        It "Convertit un FileTime valide en DateTime" {
            # 133500000000000000 = environ 2024-01-15 en FileTime
            $fileTime = 133500000000000000
            $user = [PSCustomObject]@{
                SamAccountName = "jdupont"
                LastLogon      = $fileTime
            }

            $result = Get-ADUserLastLogon -User $user

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [DateTime]
        }

        It "Retourne une date coherente pour un FileTime connu" {
            # FileTime pour 2025-01-01 00:00:00 UTC
            $knownDate = [DateTime]::SpecifyKind([DateTime]"2025-01-01 00:00:00", [System.DateTimeKind]::Utc)
            $fileTime  = $knownDate.ToFileTime()

            $user = [PSCustomObject]@{
                SamAccountName = "jdupont"
                LastLogon      = $fileTime
            }

            $result = Get-ADUserLastLogon -User $user

            $result.Year  | Should -Be 2025
            $result.Month | Should -Be 1
            $result.Day   | Should -Be 1
        }
    }

    Context "Utilisateur jamais connecte" {

        It "Retourne null si LastLogon vaut 0" {
            $user = [PSCustomObject]@{
                SamAccountName = "nouveau"
                LastLogon      = 0
            }

            $result = Get-ADUserLastLogon -User $user

            $result | Should -BeNullOrEmpty
        }

        It "Retourne null si LastLogon est null" {
            $user = [PSCustomObject]@{
                SamAccountName = "nouveau"
                LastLogon      = $null
            }

            $result = Get-ADUserLastLogon -User $user

            $result | Should -BeNullOrEmpty
        }
    }

    Context "Robustesse face aux donnees invalides" {

        It "Retourne null si LastLogon est une valeur invalide" {
            $user = [PSCustomObject]@{
                SamAccountName = "corrupt"
                LastLogon      = -1
            }

            $result = Get-ADUserLastLogon -User $user

            $result | Should -BeNullOrEmpty
        }
    }
}

# ========================================
# Get-ADCredentialFromConfig
# ========================================

Describe "Get-ADCredentialFromConfig" {

    It "Retourne un PSCredential valide" {
        $result = Get-ADCredentialFromConfig -Username "DOMAIN\admin" -Password "Secret123"

        $result | Should -BeOfType [PSCredential]
    }

    It "Le username est correct dans le credential" {
        $result = Get-ADCredentialFromConfig -Username "DOMAIN\admin" -Password "Secret123"

        $result.UserName | Should -Be "DOMAIN\admin"
    }

    It "Le mot de passe est stocke dans un SecureString" {
        $result = Get-ADCredentialFromConfig -Username "DOMAIN\admin" -Password "Secret123"

        $result.Password | Should -BeOfType [System.Security.SecureString]
    }
}
