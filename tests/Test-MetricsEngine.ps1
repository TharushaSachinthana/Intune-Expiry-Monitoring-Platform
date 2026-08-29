<#
.SYNOPSIS
    Unit tests for the Expiry Metrics calculation engine.

.DESCRIPTION
    Validates Calculate-ExpiryMetrics.ps1 with known input values
    and asserts correct DaysRemaining, IsInRenewalWindow, and TrendDirection outputs.
    No Microsoft Graph connection is required.

.EXAMPLE
    .\tests\Test-MetricsEngine.ps1
#>

$ErrorActionPreference = "Stop"

# Load the module
. ".\src\metrics\Calculate-ExpiryMetrics.ps1"
. ".\src\processors\Normalize-ResourceData.ps1"

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

function Assert-True {
    param ([string]$TestName, [bool]$Condition)
    Assert-Equal -TestName $TestName -Expected $true -Actual $Condition
}

function Build-MockNormalized {
    param ([int]$DaysOffset, [string]$ResourceType = "APNsCertificate")
    $ExpirationDate  = (Get-Date).AddDays($DaysOffset).AddMinutes(1).ToUniversalTime()
    $LastModified    = (Get-Date).AddDays($DaysOffset - 365).ToUniversalTime()

    return [PSCustomObject]@{
        ResourceType         = $ResourceType
        ResourceId           = [System.Guid]::NewGuid().ToString()
        DisplayName          = "Test $ResourceType"
        ExpirationDate       = $ExpirationDate
        LastModifiedDate     = $LastModified
        RetrievedAt          = (Get-Date).ToUniversalTime()
        AdditionalProperties = @{}
        ProcessingErrors     = @()
        IsValid              = $true
    }
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Metrics Engine Unit Tests" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# ─── TEST CASES ───────────────────────────────────────────────────────────────

# Test 1: Positive days remaining
$mock = Build-MockNormalized -DaysOffset 30
$metric = Calculate-ExpiryMetrics -NormalizedData $mock
Assert-Equal -TestName "DaysRemaining = 30 for 30-day offset" -Expected 30 -Actual $metric.DaysRemaining
Assert-True  -TestName "MetricValid is true"                                 -Condition $metric.MetricValid
Assert-True  -TestName "IsInRenewalWindow = true for 30 days (window=30)"   -Condition ($metric.IsInRenewalWindow -eq $true)
Assert-True  -TestName "IsExpired = false"                                   -Condition ($metric.IsExpired -eq $false)

# Test 2: Urgent range (5 days)
$mock5 = Build-MockNormalized -DaysOffset 5
$metric5 = Calculate-ExpiryMetrics -NormalizedData $mock5
Assert-Equal -TestName "DaysRemaining = 5 for 5-day offset"  -Expected 5 -Actual $metric5.DaysRemaining
Assert-Equal -TestName "TrendDirection = Declining-Critical" -Expected "Declining-Critical" -Actual $metric5.TrendDirection

# Test 3: Healthy range (100 days)
$mock100 = Build-MockNormalized -DaysOffset 100
$metric100 = Calculate-ExpiryMetrics -NormalizedData $mock100
Assert-Equal -TestName "DaysRemaining = 100 for 100-day offset"      -Expected 100 -Actual $metric100.DaysRemaining
Assert-Equal -TestName "TrendDirection = Stable for 100 days"        -Expected "Stable" -Actual $metric100.TrendDirection
Assert-True  -TestName "IsInRenewalWindow = false for 100 days"      -Condition ($metric100.IsInRenewalWindow -eq $false)

# Test 4: Expired (negative days)
$mockExpired = Build-MockNormalized -DaysOffset -5
$metricExpired = Calculate-ExpiryMetrics -NormalizedData $mockExpired
Assert-True  -TestName "IsExpired = true for negative days"          -Condition ($metricExpired.IsExpired -eq $true)
Assert-Equal -TestName "TrendDirection = Expired"                    -Expected "Expired" -Actual $metricExpired.TrendDirection

# Test 5: Invalid normalized data (no expiry)
$mockInvalid = [PSCustomObject]@{
    ResourceType = "APNsCertificate"; ResourceId = "test"; DisplayName = "Test"; ExpirationDate = $null; IsValid = $false; ProcessingErrors = @("No date")
}
$metricInvalid = Calculate-ExpiryMetrics -NormalizedData $mockInvalid
Assert-True  -TestName "MetricValid = false for invalid data"        -Condition ($metricInvalid.MetricValid -eq $false)

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
$ResultColor = if ($FailCount -eq 0) { "Green" } else { "Red" }
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  Results: $PassCount passed  |  $FailCount failed" -ForegroundColor $ResultColor
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

if ($FailCount -gt 0) { exit 1 }
