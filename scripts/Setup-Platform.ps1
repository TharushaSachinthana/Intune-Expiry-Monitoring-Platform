<#
.SYNOPSIS
    Platform setup and validation script for the Intune Expiry Monitoring Platform.

.DESCRIPTION
    Validates the environment before running the monitoring platform:
        1. Checks PowerShell version (requires 5.1+)
        2. Validates all required source files exist
        3. Validates config/monitoring_config.json structure
        4. Validates config/thresholds.json
        5. Checks that placeholder credentials have been replaced
        6. Optionally tests authentication (with -TestAuth flag)
        7. Creates required directories (logs/, dashboard/data/)

.PARAMETER TestAuth
    If specified, attempts to acquire a Graph token to validate credentials.

.EXAMPLE
    # Validate environment only (no Graph call)
    .\scripts\Setup-Platform.ps1

    # Validate and test authentication
    .\scripts\Setup-Platform.ps1 -TestAuth

.NOTES
    Run this script once after cloning the repository and configuring
    monitoring_config.json with your Entra ID App Registration details.
#>

[CmdletBinding()]
param (
    [switch]$TestAuth
)

$ErrorActionPreference = "Continue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$PassCount = 0
$FailCount = 0
$WarnCount = 0

function Write-Check {
    param ([string]$Label, [bool]$Passed, [string]$Detail = "", [bool]$IsWarning = $false)
    if ($Passed) {
        Write-Host "  ✓ $Label" -ForegroundColor Green
        $script:PassCount++
    }
    elseif ($IsWarning) {
        Write-Host "  ⚠ $Label" -ForegroundColor Yellow
        if ($Detail) { Write-Host "    $Detail" -ForegroundColor Yellow }
        $script:WarnCount++
    }
    else {
        Write-Host "  ✗ $Label" -ForegroundColor Red
        if ($Detail) { Write-Host "    → $Detail" -ForegroundColor DarkRed }
        $script:FailCount++
    }
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║    Intune Expiry Monitoring Platform — Setup Check       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─── 1. POWERSHELL VERSION ────────────────────────────────────────────────────
Write-Host "  [1/7] PowerShell Version" -ForegroundColor DarkGray
$PSVersion = $PSVersionTable.PSVersion
Write-Check -Label "PowerShell $($PSVersion.Major).$($PSVersion.Minor) (requires 5.1+)" `
    -Passed ($PSVersion.Major -ge 5 -and ($PSVersion.Major -gt 5 -or $PSVersion.Minor -ge 1)) `
    -Detail "Upgrade PowerShell: https://docs.microsoft.com/powershell"

# ─── 2. REQUIRED FILES ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [2/7] Required Source Files" -ForegroundColor DarkGray

$RequiredFiles = @(
    "src\auth\Get-GraphToken.ps1",
    "src\collectors\Get-APNSCertificate.ps1",
    "src\processors\Invoke-ResourceProcessor.ps1",
    "src\processors\Normalize-ResourceData.ps1",
    "src\metrics\Calculate-ExpiryMetrics.ps1",
    "src\evaluation\Invoke-ThresholdEvaluation.ps1",
    "src\core\Invoke-MonitoringRun.ps1",
    "src\core\Write-MonitoringLog.ps1",
    "src\core\Export-MonitoringReport.ps1",
    "src\alerting\Send-EmailAlert.ps1",
    "src\alerting\Send-TeamsAlert.ps1",
    "src\alerting\Send-ServiceNowAlert.ps1",
    "config\monitoring_config.json",
    "config\thresholds.json",
    "config\resources\apns_resource.json",
    "dashboard\index.html",
    "dashboard\assets\styles.css",
    "dashboard\assets\app.js"
)

foreach ($File in $RequiredFiles) {
    $FullPath = Join-Path $ProjectRoot $File
    Write-Check -Label $File -Passed (Test-Path $FullPath) -Detail "File missing: $FullPath"
}

# ─── 3. CONFIG VALIDATION ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [3/7] Configuration Validation" -ForegroundColor DarkGray

$ConfigPath = Join-Path $ProjectRoot "config\monitoring_config.json"
if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Check -Label "monitoring_config.json is valid JSON" -Passed $true

        # Check required fields
        Write-Check -Label "authentication.tenantId present" `
            -Passed (-not [string]::IsNullOrEmpty($Config.authentication.tenantId))
        Write-Check -Label "authentication.clientId present" `
            -Passed (-not [string]::IsNullOrEmpty($Config.authentication.clientId))
        Write-Check -Label "authentication.clientSecret present" `
            -Passed (-not [string]::IsNullOrEmpty($Config.authentication.clientSecret))
    }
    catch {
        Write-Check -Label "monitoring_config.json is valid JSON" -Passed $false -Detail $_.Exception.Message
    }
}
else {
    Write-Check -Label "monitoring_config.json exists" -Passed $false -Detail "File not found: $ConfigPath"
}

# ─── 4. THRESHOLDS VALIDATION ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  [4/7] Thresholds Configuration" -ForegroundColor DarkGray

$ThresholdsPath = Join-Path $ProjectRoot "config\thresholds.json"
if (Test-Path $ThresholdsPath) {
    try {
        $Thresholds = Get-Content $ThresholdsPath -Raw | ConvertFrom-Json
        Write-Check -Label "thresholds.json is valid JSON" -Passed $true
        Write-Check -Label "thresholds array has 4 states" `
            -Passed ($Thresholds.thresholds.Count -eq 4)
    }
    catch {
        Write-Check -Label "thresholds.json is valid JSON" -Passed $false -Detail $_.Exception.Message
    }
}

# ─── 5. PLACEHOLDER CHECK ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [5/7] Placeholder Credential Check" -ForegroundColor DarkGray

if (Test-Path $ConfigPath) {
    $ConfigRaw = Get-Content $ConfigPath -Raw
    Write-Check -Label "Tenant ID is not a placeholder" `
        -Passed ($ConfigRaw -notmatch "YOUR_TENANT_ID") `
        -Detail "Update tenantId in config\monitoring_config.json" `
        -IsWarning $true
    Write-Check -Label "Client ID is not a placeholder" `
        -Passed ($ConfigRaw -notmatch "YOUR_CLIENT_ID") `
        -Detail "Update clientId in config\monitoring_config.json" `
        -IsWarning $true
    Write-Check -Label "Client Secret is not a placeholder" `
        -Passed ($ConfigRaw -notmatch "YOUR_CLIENT_SECRET") `
        -Detail "Update clientSecret in config\monitoring_config.json" `
        -IsWarning $true
}

# ─── 6. DIRECTORY SETUP ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [6/7] Directory Setup" -ForegroundColor DarkGray

$Directories = @(
    "logs",
    "dashboard\data"
)

foreach ($Dir in $Directories) {
    $DirPath = Join-Path $ProjectRoot $Dir
    if (-not (Test-Path $DirPath)) {
        New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
        Write-Host "  ✓ Created: $Dir" -ForegroundColor Green
    }
    else {
        Write-Host "  ✓ Exists:  $Dir" -ForegroundColor Green
    }
    $script:PassCount++
}

# ─── 7. OPTIONAL AUTH TEST ────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [7/7] Authentication Test" -ForegroundColor DarkGray

if ($TestAuth) {
    . (Join-Path $ProjectRoot "src\auth\Get-GraphToken.ps1")
    if (Test-Path $ConfigPath) {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        try {
            $Token = Get-GraphToken `
                -TenantId     $Config.authentication.tenantId `
                -ClientId     $Config.authentication.clientId `
                -ClientSecret $Config.authentication.clientSecret

            Write-Check -Label "Graph token acquired successfully" -Passed ($null -ne $Token.AccessToken)
            Write-Host "    Token expires: $($Token.ExpiresAt.ToString('HH:mm:ss UTC'))" -ForegroundColor DarkGray
        }
        catch {
            Write-Check -Label "Graph token acquisition" -Passed $false -Detail $_.Exception.Message
        }
    }
}
else {
    Write-Host "  → Skipped (use -TestAuth flag to validate credentials)" -ForegroundColor DarkGray
}

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Setup Check Results" -ForegroundColor Cyan
Write-Host "  ══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✓ Passed  : $PassCount" -ForegroundColor Green
Write-Host "  ⚠ Warnings: $WarnCount" -ForegroundColor Yellow
Write-Host "  ✗ Failed  : $FailCount" -ForegroundColor $(if ($FailCount -gt 0) {"Red"} else {"Green"})
Write-Host ""

if ($WarnCount -gt 0) {
    Write-Host "  Next step: Update config\monitoring_config.json with your Entra ID App Registration details." -ForegroundColor Yellow
    Write-Host "  Then run: .\src\core\Invoke-MonitoringRun.ps1 -DryRun" -ForegroundColor Yellow
}

if ($FailCount -eq 0 -and $WarnCount -eq 0) {
    Write-Host "  ✓ Platform is ready. Run: .\src\core\Invoke-MonitoringRun.ps1 -DryRun" -ForegroundColor Green
}
Write-Host ""
