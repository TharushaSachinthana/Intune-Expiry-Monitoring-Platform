<#
.SYNOPSIS
    Calculates expiry monitoring metrics from normalized resource data.

.DESCRIPTION
    The Metrics Layer converts expiration information into operational monitoring metrics.

    Metric Flow:
        Expiration Date
               |
        Days Remaining
               |
        Monitoring Metric
               |
        Severity (passed to Evaluation Layer)

    Calculated Metrics:
        - DaysRemaining      : Total calendar days until expiration
        - HoursRemaining     : Precise hours until expiration
        - RenewalWindowDays  : Recommended renewal window for this resource type
        - IsInRenewalWindow  : True if DaysRemaining <= RenewalWindowDays
        - ExpirationPercent  : Percentage of total certificate lifetime remaining
        - TrendDirection     : Increasing / Stable / Decreasing (for future trend analysis)
        - CalculatedAt       : UTC timestamp of metric calculation

.PARAMETER NormalizedData
    The PSCustomObject output from Normalize-ResourceData.ps1.

.PARAMETER ThresholdsConfig
    Optional path to thresholds.json for renewal window lookup.
    Defaults to '.\config\thresholds.json'.

.OUTPUTS
    PSCustomObject - monitoring metric object.

.EXAMPLE
    $Normalized = Normalize-ResourceData -ExtractedProperties $Extracted -RetrievedAt $Raw.RetrievedAt
    $Metrics    = Calculate-ExpiryMetrics -NormalizedData $Normalized
#>

function Calculate-ExpiryMetrics {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$NormalizedData,

        [Parameter(Mandatory = $false)]
        [string]$ThresholdsConfigPath = ".\config\thresholds.json"
    )

    $ResourceType = $NormalizedData.ResourceType
    $DisplayName  = $NormalizedData.DisplayName

    Write-Verbose "[Metrics] Calculating expiry metrics for: $ResourceType - $DisplayName"

    # -------------------------------------------------------------------------
    # Validate resource has expiration data
    # -------------------------------------------------------------------------
    if (-not $NormalizedData.IsValid -or $null -eq $NormalizedData.ExpirationDate) {
        Write-Warning "[Metrics] Resource '$DisplayName' has no valid expiration date. Skipping metric calculation."
        return [PSCustomObject]@{
            ResourceType        = $ResourceType
            ResourceId          = $NormalizedData.ResourceId
            DisplayName         = $DisplayName
            ExpirationDate      = $null
            DaysRemaining       = $null
            HoursRemaining      = $null
            RenewalWindowDays   = $null
            IsInRenewalWindow   = $null
            ExpirationPercent   = $null
            IsExpired           = $null
            TrendDirection      = "Unknown"
            CalculatedAt        = (Get-Date).ToUniversalTime()
            MetricValid         = $false
            MetricErrors        = $NormalizedData.ProcessingErrors
        }
    }

    # -------------------------------------------------------------------------
    # Core metric: Days Remaining
    # -------------------------------------------------------------------------
    $Now            = (Get-Date).ToUniversalTime()
    $TimeSpan       = $NormalizedData.ExpirationDate - $Now
    $DaysRemaining  = [math]::Floor($TimeSpan.TotalDays)
    $HoursRemaining = [math]::Floor($TimeSpan.TotalHours)
    $IsExpired      = $DaysRemaining -lt 0

    Write-Verbose "[Metrics:$ResourceType] Days remaining: $DaysRemaining"
    Write-Verbose "[Metrics:$ResourceType] Expiration date: $($NormalizedData.ExpirationDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"

    # -------------------------------------------------------------------------
    # Renewal window lookup from thresholds config
    # -------------------------------------------------------------------------
    $RenewalWindowDays = 30  # Default

    if (Test-Path $ThresholdsConfigPath) {
        try {
            $ThresholdsConfig  = Get-Content $ThresholdsConfigPath -Raw | ConvertFrom-Json
            $ResourceRenewal   = $ThresholdsConfig.renewalWindows.$ResourceType
            if ($null -ne $ResourceRenewal) {
                $RenewalWindowDays = $ResourceRenewal
            }
        }
        catch {
            Write-Verbose "[Metrics] Could not load thresholds config for renewal window. Using default: $RenewalWindowDays days."
        }
    }

    $IsInRenewalWindow = $DaysRemaining -le $RenewalWindowDays

    # -------------------------------------------------------------------------
    # Expiration percentage (estimate based on 1-year certificate lifetime)
    # -------------------------------------------------------------------------
    $ExpirationPercent = $null
    if ($null -ne $NormalizedData.LastModifiedDate) {
        $TotalLifetimeDays  = ($NormalizedData.ExpirationDate - $NormalizedData.LastModifiedDate).TotalDays
        if ($TotalLifetimeDays -gt 0) {
            $RemainingPercent   = ($DaysRemaining / $TotalLifetimeDays) * 100
            $ExpirationPercent  = [math]::Round([math]::Max(0, [math]::Min(100, $RemainingPercent)), 2)
        }
    }

    # -------------------------------------------------------------------------
    # Trend direction (foundation for future trend analysis)
    # -------------------------------------------------------------------------
    $TrendDirection = if ($IsExpired) { "Expired" }
                      elseif ($DaysRemaining -le 7)  { "Declining-Critical" }
                      elseif ($DaysRemaining -le 30) { "Declining-Warning"  }
                      else                           { "Stable"              }

    # -------------------------------------------------------------------------
    # Build metric output object
    # -------------------------------------------------------------------------
    $Metric = [PSCustomObject]@{
        ResourceType        = $ResourceType
        ResourceId          = $NormalizedData.ResourceId
        DisplayName         = $DisplayName
        ExpirationDate      = $NormalizedData.ExpirationDate
        DaysRemaining       = $DaysRemaining
        HoursRemaining      = $HoursRemaining
        RenewalWindowDays   = $RenewalWindowDays
        IsInRenewalWindow   = $IsInRenewalWindow
        ExpirationPercent   = $ExpirationPercent
        IsExpired           = $IsExpired
        TrendDirection      = $TrendDirection
        CalculatedAt        = $Now
        MetricValid         = $true
        MetricErrors        = @()
    }

    Write-Verbose "[Metrics:$ResourceType] Metric calculated. IsExpired: $IsExpired | IsInRenewalWindow: $IsInRenewalWindow | TrendDirection: $TrendDirection"

    return $Metric
}
