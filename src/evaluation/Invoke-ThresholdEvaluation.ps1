<#
.SYNOPSIS
    Evaluates monitoring metrics against predefined thresholds and determines the health state.

.DESCRIPTION
    The Evaluation Layer classifies each monitored resource into one of four health states
    based on the DaysRemaining metric and the configured threshold model.

    Threshold Model:
        > 90 Days   -> HEALTHY   (No action required)
        31-90 Days  -> WARNING   (Plan renewal)
        8-30 Days   -> CRITICAL  (Action required within renewal window)
        <= 7 Days   -> URGENT    (Immediate action required)

    Evaluation Flow:
        DaysRemaining
               |
        Compare Against Thresholds
               |
        HealthState (HEALTHY / WARNING / CRITICAL / URGENT)
               |
        EvaluationResult (passed to Alerting Layer)

.PARAMETER Metric
    The PSCustomObject output from Calculate-ExpiryMetrics.ps1.

.PARAMETER ThresholdsConfigPath
    Path to thresholds.json. Defaults to '.\config\thresholds.json'.

.OUTPUTS
    PSCustomObject - evaluation result with HealthState, severity details, and alert recommendation.

.EXAMPLE
    $Metric     = Calculate-ExpiryMetrics -NormalizedData $Normalized
    $Evaluation = Invoke-ThresholdEvaluation -Metric $Metric
#>

function Invoke-ThresholdEvaluation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$Metric,

        [Parameter(Mandatory = $false)]
        [string]$ThresholdsConfigPath = ".\config\thresholds.json"
    )

    $ResourceType = $Metric.ResourceType
    $DisplayName  = $Metric.DisplayName

    Write-Verbose "[Evaluation] Evaluating health state for: $ResourceType - $DisplayName"

    # -------------------------------------------------------------------------
    # Handle invalid metrics (no expiry data)
    # -------------------------------------------------------------------------
    if (-not $Metric.MetricValid -or $null -eq $Metric.DaysRemaining) {
        Write-Warning "[Evaluation] Metric for '$DisplayName' is not valid. Cannot evaluate health state."
        return [PSCustomObject]@{
            ResourceType       = $ResourceType
            ResourceId         = $Metric.ResourceId
            DisplayName        = $DisplayName
            DaysRemaining      = $null
            ExpirationDate     = $null
            HealthState        = "UNKNOWN"
            HealthStateLabel   = "Unknown"
            HealthStateColor   = "#6A737D"
            HealthStateIcon    = "[?]"
            Priority           = 99
            ActionRequired     = $false
            AlertChannels      = @()
            Description        = "Unable to determine health state - no valid expiry metric."
            EvaluatedAt        = (Get-Date).ToUniversalTime()
            EvaluationValid    = $false
        }
    }

    # -------------------------------------------------------------------------
    # Load threshold configuration
    # -------------------------------------------------------------------------
    $Thresholds = $null

    if (Test-Path $ThresholdsConfigPath) {
        try {
            $ThresholdConfig = Get-Content $ThresholdsConfigPath -Raw | ConvertFrom-Json
            $Thresholds      = $ThresholdConfig.thresholds
            Write-Verbose "[Evaluation] Loaded $($Thresholds.Count) thresholds from config."
        }
        catch {
            Write-Warning "[Evaluation] Failed to load thresholds config. Using hardcoded defaults."
        }
    }

    # -------------------------------------------------------------------------
    # Hardcoded fallback thresholds (matches thresholds.json defaults)
    # -------------------------------------------------------------------------
    if ($null -eq $Thresholds) {
        $Thresholds = @(
            [PSCustomObject]@{ state = "URGENT";   label = "Urgent";   minDays = 0;  maxDays = 7;    color = "#D73A49"; icon = "[U]"; priority = 1; description = "Immediate action required."; actionRequired = $true;  alertChannels = @("email","teams","servicenow") }
            [PSCustomObject]@{ state = "CRITICAL"; label = "Critical"; minDays = 8;  maxDays = 30;   color = "#E36209"; icon = "[C]"; priority = 2; description = "Action required within renewal window."; actionRequired = $true;  alertChannels = @("email","teams") }
            [PSCustomObject]@{ state = "WARNING";  label = "Warning";  minDays = 31; maxDays = 90;   color = "#F0AD4E"; icon = "[W]"; priority = 3; description = "Plan renewal. Approaching expiry window."; actionRequired = $false; alertChannels = @("email") }
            [PSCustomObject]@{ state = "HEALTHY";  label = "Healthy";  minDays = 91; maxDays = $null; color = "#2EA44F"; icon = "[H]"; priority = 4; description = "Asset is valid and not approaching expiry."; actionRequired = $false; alertChannels = @() }
        )
    }

    $DaysRemaining = $Metric.DaysRemaining

    Write-Verbose "[Evaluation:$ResourceType] Evaluating $DaysRemaining days remaining against thresholds..."

    # -------------------------------------------------------------------------
    # Evaluate against thresholds (ordered from most severe to least severe)
    # -------------------------------------------------------------------------
    $MatchedThreshold = $null

    foreach ($Threshold in ($Thresholds | Sort-Object priority)) {
        $MinDays = $Threshold.minDays
        $MaxDays = if ($null -ne $Threshold.maxDays) { $Threshold.maxDays } else { [int]::MaxValue }

        if ($DaysRemaining -ge $MinDays -and $DaysRemaining -le $MaxDays) {
            $MatchedThreshold = $Threshold
            break
        }
    }

    # Handle expired assets (DaysRemaining < 0)
    if ($null -eq $MatchedThreshold -or $DaysRemaining -lt 0) {
        $MatchedThreshold = [PSCustomObject]@{
            state          = "EXPIRED"
            label          = "Expired"
            color          = "#8B0000"
            icon           = "[X]"
            priority       = 0
            description    = "Asset has expired. Device management operations may be impacted."
            actionRequired = $true
            alertChannels  = @("email","teams","servicenow")
        }
    }

    Write-Verbose "[Evaluation:$ResourceType] Health state determined: $($MatchedThreshold.state)"

    # -------------------------------------------------------------------------
    # Build evaluation result object
    # -------------------------------------------------------------------------
    $EvaluationResult = [PSCustomObject]@{
        ResourceType       = $ResourceType
        ResourceId         = $Metric.ResourceId
        DisplayName        = $DisplayName
        DaysRemaining      = $DaysRemaining
        HoursRemaining     = $Metric.HoursRemaining
        ExpirationDate     = $Metric.ExpirationDate
        IsExpired          = $Metric.IsExpired
        IsInRenewalWindow  = $Metric.IsInRenewalWindow
        RenewalWindowDays  = $Metric.RenewalWindowDays
        ExpirationPercent  = $Metric.ExpirationPercent
        TrendDirection     = $Metric.TrendDirection
        HealthState        = $MatchedThreshold.state
        HealthStateLabel   = $MatchedThreshold.label
        HealthStateColor   = $MatchedThreshold.color
        HealthStateIcon    = $MatchedThreshold.icon
        Priority           = $MatchedThreshold.priority
        ActionRequired     = $MatchedThreshold.actionRequired
        AlertChannels      = $MatchedThreshold.alertChannels
        Description        = $MatchedThreshold.description
        EvaluatedAt        = (Get-Date).ToUniversalTime()
        EvaluationValid    = $true
    }

    # -------------------------------------------------------------------------
    # Emit summary to console
    # -------------------------------------------------------------------------
    $Icon      = $MatchedThreshold.icon
    $StateLabel = $MatchedThreshold.label

    Write-Host ""
    Write-Host "  $Icon  $DisplayName" -ForegroundColor White
    Write-Host "      Health State  : $StateLabel" -ForegroundColor $(
        switch ($MatchedThreshold.state) {
            "HEALTHY"  { "Green"  }
            "WARNING"  { "Yellow" }
            "CRITICAL" { "DarkYellow" }
            "URGENT"   { "Red"    }
            "EXPIRED"  { "DarkRed" }
            default    { "Gray"   }
        }
    )
    Write-Host "      Days Remaining: $DaysRemaining"
    Write-Host "      Expires       : $($Metric.ExpirationDate.ToString('dd MMM yyyy'))"
    Write-Host "      Action        : $(if ($MatchedThreshold.actionRequired) { 'Required' } else { 'Not Required' })"
    Write-Host ""

    return $EvaluationResult
}
