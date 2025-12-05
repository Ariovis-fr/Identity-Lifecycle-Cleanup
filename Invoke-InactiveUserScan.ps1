# ========================================
# Entry Point
# ========================================

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config\.env",

    [int]$InactiveDays,

    [switch]$SkipAD,

    [switch]$SkipEntraId

)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INACTIVE USERS SCAN" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load modules
Import-Module "$PSScriptRoot\src\Core\Configuration.psm1" -Force
Import-Module "$PSScriptRoot\src\Providers\ActiveDirectoryProvider.psm1" -Force
Import-Module "$PSScriptRoot\src\Providers\EntraIdProvider.psm1" -Force
Import-Module "$PSScriptRoot\src\Providers\DatabaseProvider.psm1" -Force
Import-Module "$PSScriptRoot\src\Services\UserActivityService.psm1" -Force
Import-Module "$PSScriptRoot\src\Services\ReportService.psm1" -Force

# ========================================
# STEP 1: Load configuration
# ========================================

Write-Host "[1/5] Loading configuration..." -ForegroundColor Yellow

try {
    $config = Get-AppConfiguration -ConfigPath $ConfigPath

    # Override with parameters if provided
    if ($InactiveDays) {
        $config | Add-Member -NotePropertyName 'INACTIVE_DAYS_THRESHOLD' -NotePropertyValue $InactiveDays -Force
    }

    $inactiveDaysThreshold = if ($config.INACTIVE_DAYS_THRESHOLD) {
        [int]$config.INACTIVE_DAYS_THRESHOLD
    } else {
        75
    }

    Write-Host "  [OK] Configuration loaded" -ForegroundColor Green
    Write-Host "  Inactivity threshold: $inactiveDaysThreshold days" -ForegroundColor Gray

} catch {
    Write-Host "  [ERROR] $_" -ForegroundColor Red
    exit 1
}

# ========================================
# STEP 2: Retrieve Entra ID users
# ========================================

$entraUsers = @()

if (-not $SkipEntraId -and $config.TENANT_ID) {
    Write-Host ""
    Write-Host "[2/5] Retrieving Entra ID users..." -ForegroundColor Yellow

    try {
        $entraUsers = Get-InactiveEntraIdUsers `
            -InactiveDays $inactiveDaysThreshold `
            -TenantId $config.TENANT_ID `
            -ClientId $config.CLIENT_ID `
            -ClientSecret $config.CLIENT_SECRET

        Write-Host "  [OK] $($entraUsers.Count) inactive users found" -ForegroundColor Green

        # Save to database if users found
        if ($entraUsers.Count -gt 0) {
            $connectionString = "Server=$($config.SQL_SERVER);Database=$($config.SQL_DATABASE);User Id=$($config.SQL_USERNAME);Password=$($config.SQL_PASSWORD);TrustServerCertificate=True;"
            $inserted = Save-EntraIdUsersToDatabase -Users $entraUsers -ConnectionString $connectionString
            Write-Host "  [OK] $inserted users saved to database" -ForegroundColor Green
        }

    } catch {
        Write-Host "  [WARNING] Entra ID skipped (see error above)" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[2/5] Entra ID skipped (missing configuration or -SkipEntraId)" -ForegroundColor Yellow
}

# ========================================
# STEP 3: Retrieve Active Directory users
# ========================================

$adUsers = @()

if (-not $SkipAD -and $config.AD_SERVER) {
    Write-Host ""
    Write-Host "[3/5] Retrieving Active Directory users..." -ForegroundColor Yellow

    try {
        $adCred = Get-ADCredentialFromConfig -Username $config.AD_USERNAME -Password $config.AD_PASSWORD

        # Prepare parameters for Get-InactiveADUsers
        $adParams = @{
            InactiveDays = $inactiveDaysThreshold
            Server       = $config.AD_SERVER
            Credential   = $adCred
        }

        # Add SearchBase if configured (to target specific OU like People)
        if ($config.AD_SEARCHBASE) {
            $adParams['SearchBase'] = $config.AD_SEARCHBASE
            Write-Host "  Searching in OU: $($config.AD_SEARCHBASE)" -ForegroundColor Gray
        }

        $adUsers = Get-InactiveADUsers @adParams

        Write-Host "  [OK] $($adUsers.Count) inactive users found" -ForegroundColor Green

        # Save to database if users found
        if ($adUsers.Count -gt 0) {
            $connectionString = "Server=$($config.SQL_SERVER);Database=$($config.SQL_DATABASE);User Id=$($config.SQL_USERNAME);Password=$($config.SQL_PASSWORD);TrustServerCertificate=True;"
            $inserted = Save-ADUsersToDatabase -Users $adUsers -ConnectionString $connectionString
            Write-Host "  [OK] $inserted users saved to database" -ForegroundColor Green
        }

    } catch {
        Write-Host "  [WARNING] Active Directory skipped: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[3/5] Active Directory skipped (missing configuration or -SkipAD)" -ForegroundColor Yellow
}

# ========================================
# STEP 4: Compare and analyze
# ========================================

Write-Host ""
Write-Host "[4/5] Comparing and analyzing..." -ForegroundColor Yellow

if ($adUsers.Count -eq 0 -and $entraUsers.Count -eq 0) {
    Write-Host "  [INFO] No inactive users found" -ForegroundColor Cyan
    exit 0
}

# Compare users present in both systems
$matchedUsers = Compare-InactiveUsers -ADUsers $adUsers -EntraIdUsers $entraUsers -Verbose:($VerbosePreference -eq 'Continue')

Write-Host "  [OK] $($matchedUsers.Count) inactive users in BOTH systems" -ForegroundColor Green

if ($matchedUsers.Count -eq 0) {
    Write-Host "  [INFO] No users inactive in both systems simultaneously" -ForegroundColor Cyan
    exit 0
}


# ========================================
# STEP 5: Generate report
# ========================================

Write-Host ""
Write-Host "[5/5] Generating report..." -ForegroundColor Yellow

# Determine output path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputPath = "$PSScriptRoot\reports\InactiveUsers_$timestamp.txt"

# Create directory if needed
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Extract users
$usersToReport = $matchedUsers

# Generate report
try {
    $reportPath = Export-InactiveUsersReport -Users $usersToReport -OutputPath $OutputPath

    Write-Host "  [OK] Report generated: $reportPath" -ForegroundColor Green

} catch {
    Write-Host "  [ERROR] Report generation: $_" -ForegroundColor Red
    exit 1
}

# ========================================
# Final Summary
# ========================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "COMPLETED!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Inactive AD users      : $($adUsers.Count)" -ForegroundColor White
Write-Host "  Inactive Entra users   : $($entraUsers.Count)" -ForegroundColor White
Write-Host "  Matched (both systems) : $($matchedUsers.Count)" -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "Report: $reportPath" -ForegroundColor White
Write-Host ""
