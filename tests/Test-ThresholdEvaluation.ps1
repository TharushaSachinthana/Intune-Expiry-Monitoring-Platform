<#
.SYNOPSIS
    Unit tests for the Threshold Evaluation engine.

.DESCRIPTION
    Validates that Invoke-ThresholdEvaluation.ps1 correctly classifies
    DaysRemaining values into the expected HealthState.

    Uses hardcoded thresholds — no config file or Graph connection required.

.EXAMPLE
    .\tests\Test-ThresholdEvaluation.ps1
#>

$ErrorActionPreference = "Stop"

. ".\src\evaluation\Invoke-ThresholdEvaluation.ps1"

$PassCount = 0
$FailCount = 0

function Assert-Equal {
    param ([string]$TestName, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        $script:PassCount++
    }
    else {
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "    Expected: $Expected" -ForegroundColor Yellow
        Write-Host "    Actual  : $Actual"   -ForegroundColor Yellow
        $script:FailCount++
    }
}

function Build-MockMetric {
    param ([int]$DaysRemaining, [bool]$IsExpired = $false)
    return [PSCustomObject]@{
        ResourceType     = "APNsCertificate"
        ResourceId       = "test-001"
        DisplayName      = "Test Certificate"
        DaysRemaining    = $DaysRemaining
        HoursRemaining   = $DaysRemaining * 24
        ExpirationDate   = (Get-Date).AddDays($DaysRemaining).ToUniversalTime()
        IsExpired        = $IsExpired
        IsInRenewalWindow = ($DaysRemaining -le 30)
        RenewalWindowDays = 30
        ExpirationPercent = 50
        TrendDirection   = "Stable"
        MetricValid      = $true
        MetricErrors     = @()
    }
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Threshold Evaluation Unit Tests" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# ─── THRESHOLD TESTS ──────────────────────────────────────────────────────────

# Using a temp config to avoid needing the full config dir
$TempThresholdsPath = [System.IO.Path]::GetTempFileName() + ".json"
$ThresholdsContent = @"
{
  "thresholds": [
    { "state": "URGENT",   "label": "Urgent",   "minDays": 0,  "maxDays": 7,    "color": "#D73A49", "icon": "🔴", "priority": 1, "description": "Immediate action.",       "actionRequired": true,  "alertChannels": ["email","teams","servicenow"] },
    { "state": "CRITICAL", "label": "Critical", "minDays": 8,  "maxDays": 30,   "color": "#E36209", "icon": "🟠", "priority": 2, "description": "Action required.",        "actionRequired": true,  "alertChannels": ["email","teams"] },
    { "state": "WARNING",  "label": "Warning",  "minDays": 31, "maxDays": 90,   "color": "#F0AD4E", "icon": "🟡", "priority": 3, "description": "Plan renewal.",           "actionRequired": false, "alertChannels": ["email"] },
    { "state": "HEALTHY",  "label": "Healthy",  "minDays": 91, "maxDays": null, "color": "#2EA44F", "icon": "🟢", "priority": 4, "description": "No action required.",     "actionRequired": false, "alertChannels": [] }
  ],
  "renewalWindows": { "APNsCertificate": 30 }
}
"@
$ThresholdsContent | Set-Content -Path $TempThresholdsPath

# Test: URGENT boundary
$metric7 = Build-MockMetric -DaysRemaining 7
$result7 = Invoke-ThresholdEvaluation -Metric $metric7 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "7 days → URGENT"   -Expected "URGENT"   -Actual $result7.HealthState

$metric1 = Build-MockMetric -DaysRemaining 1
$result1 = Invoke-ThresholdEvaluation -Metric $metric1 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "1 day → URGENT"    -Expected "URGENT"   -Actual $result1.HealthState

# Test: CRITICAL boundary
$metric8 = Build-MockMetric -DaysRemaining 8
$result8 = Invoke-ThresholdEvaluation -Metric $metric8 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "8 days → CRITICAL" -Expected "CRITICAL" -Actual $result8.HealthState

$metric30 = Build-MockMetric -DaysRemaining 30
$result30 = Invoke-ThresholdEvaluation -Metric $metric30 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "30 days → CRITICAL" -Expected "CRITICAL" -Actual $result30.HealthState

# Test: WARNING boundary
$metric31 = Build-MockMetric -DaysRemaining 31
$result31 = Invoke-ThresholdEvaluation -Metric $metric31 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "31 days → WARNING" -Expected "WARNING"  -Actual $result31.HealthState

$metric90 = Build-MockMetric -DaysRemaining 90
$result90 = Invoke-ThresholdEvaluation -Metric $metric90 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "90 days → WARNING" -Expected "WARNING"  -Actual $result90.HealthState

# Test: HEALTHY boundary
$metric91 = Build-MockMetric -DaysRemaining 91
$result91 = Invoke-ThresholdEvaluation -Metric $metric91 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "91 days → HEALTHY"  -Expected "HEALTHY"  -Actual $result91.HealthState

$metric365 = Build-MockMetric -DaysRemaining 365
$result365 = Invoke-ThresholdEvaluation -Metric $metric365 -ThresholdsConfigPath $TempThresholdsPath
Assert-Equal -TestName "365 days → HEALTHY" -Expected "HEALTHY"  -Actual $result365.HealthState

# Test: ActionRequired
Assert-Equal -TestName "URGENT ActionRequired = true"  -Expected $true  -Actual $result7.ActionRequired
Assert-Equal -TestName "HEALTHY ActionRequired = false" -Expected $false -Actual $result365.ActionRequired

# Cleanup
Remove-Item $TempThresholdsPath -Force

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
$ResultColor = if ($FailCount -eq 0) { "Green" } else { "Red" }
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Results: $PassCount passed  |  $FailCount failed" -ForegroundColor $ResultColor
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

if ($FailCount -gt 0) { exit 1 }
