# ========================================
# Tests unitaires — EntraIdProvider
# ========================================
# Invoke-Pester .\tests\Unit\Providers\EntraIdProvider.Tests.ps1 -Output Detailed

Import-Module "$PSScriptRoot\..\..\..\src\Providers\EntraIdProvider.psm1" -Force

# ========================================
# Get-EntraUserLastSignInDate
# ========================================

Describe "Get-EntraUserLastSignInDate" {

    Context "Ordre de priorite des dates SignInActivity" {

        It "Retourne LastSuccessfulSignInDateTime en priorite 1" {
            $date1 = [DateTime]::SpecifyKind([DateTime]"2025-10-01 12:00:00", [System.DateTimeKind]::Utc)
            $date2 = [DateTime]::SpecifyKind([DateTime]"2025-11-01 12:00:00", [System.DateTimeKind]::Utc)
            $date3 = [DateTime]::SpecifyKind([DateTime]"2025-12-01 12:00:00", [System.DateTimeKind]::Utc)
            $user = [PSCustomObject]@{
                SignInActivity = @{
                    LastSuccessfulSignInDateTime    = $date1
                    LastSignInDateTime              = $date2
                    LastNonInteractiveSignInDateTime = $date3
                }
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result | Should -Be $date1
        }

        It "Retourne LastSignInDateTime si LastSuccessful est null" {
            $date2 = [DateTime]::SpecifyKind([DateTime]"2025-11-01 12:00:00", [System.DateTimeKind]::Utc)
            $date3 = [DateTime]::SpecifyKind([DateTime]"2025-12-01 12:00:00", [System.DateTimeKind]::Utc)
            $user = [PSCustomObject]@{
                SignInActivity = @{
                    LastSuccessfulSignInDateTime    = $null
                    LastSignInDateTime              = $date2
                    LastNonInteractiveSignInDateTime = $date3
                }
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result | Should -Be $date2
        }

        It "Retourne LastNonInteractiveSignInDateTime en dernier recours" {
            $date3 = [DateTime]::SpecifyKind([DateTime]"2025-12-01 12:00:00", [System.DateTimeKind]::Utc)
            $user = [PSCustomObject]@{
                SignInActivity = @{
                    LastSuccessfulSignInDateTime    = $null
                    LastSignInDateTime              = $null
                    LastNonInteractiveSignInDateTime = $date3
                }
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result | Should -Be $date3
        }
    }

    Context "Cas ou aucune date n'existe" {

        It "Retourne null si SignInActivity est null" {
            $user = [PSCustomObject]@{
                SignInActivity = $null
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result | Should -BeNullOrEmpty
        }

        It "Retourne null si toutes les dates sont null" {
            $user = [PSCustomObject]@{
                SignInActivity = @{
                    LastSuccessfulSignInDateTime    = $null
                    LastSignInDateTime              = $null
                    LastNonInteractiveSignInDateTime = $null
                }
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result | Should -BeNullOrEmpty
        }

        It "Retourne null si SignInActivity est un objet vide" {
            $user = [PSCustomObject]@{
                SignInActivity = @{}
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result | Should -BeNullOrEmpty
        }
    }

    Context "Conversion UTC" {

        It "Convertit en UTC si la date n'est pas deja en UTC" {
            $localDate = [DateTime]::SpecifyKind([DateTime]"2025-06-15 14:00:00", [System.DateTimeKind]::Local)
            $user = [PSCustomObject]@{
                SignInActivity = @{
                    LastSuccessfulSignInDateTime = $localDate
                }
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It "Garde la date telle quelle si deja en UTC" {
            $utcDate = [DateTime]::SpecifyKind([DateTime]"2025-06-15 14:00:00", [System.DateTimeKind]::Utc)
            $user = [PSCustomObject]@{
                SignInActivity = @{
                    LastSuccessfulSignInDateTime = $utcDate
                }
            }

            $result = Get-EntraUserLastSignInDate -User $user

            $result.Kind | Should -Be ([System.DateTimeKind]::Utc)
            $result      | Should -Be $utcDate
        }
    }
}
