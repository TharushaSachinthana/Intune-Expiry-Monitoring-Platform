<#
.SYNOPSIS
    Exports all evaluation results to a JSON report consumed by the web dashboard.

.DESCRIPTION
    Generates a structured JSON report from the evaluation results.
    The report file is read by the HTML dashboard (dashboard/index.html)
    to render expiry status, health states, and alert information.

.PARAMETER EvaluationResults
    Array of evaluation result objects from Invoke-ThresholdEvaluation.

.PARAMETER OutputPath
    Path for the output JSON file. Defaults to '.\dashboard\data\monitoring_report.json'.

.OUTPUTS
    String — path to the generated report file.
#>

function Export-MonitoringReport {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$EvaluationResults,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = ".\dashboard\data\monitoring_report.json"
    )

    Write-Verbose "[Report] Building monitoring report from $($EvaluationResults.Count) evaluation result(s)."

    $ReportGeneratedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # -------------------------------------------------------------------------
    # Build summary statistics
    # -------------------------------------------------------------------------
    $Summary = [PSCustomObject]@{
        TotalResources   = $EvaluationResults.Count
        HealthyCount     = ($EvaluationResults | Where-Object { $_.HealthState -eq "HEALTHY"  }).Count
        WarningCount     = ($EvaluationResults | Where-Object { $_.HealthState -eq "WARNING"  }).Count
        CriticalCount    = ($EvaluationResults | Where-Object { $_.HealthState -eq "CRITICAL" }).Count
        UrgentCount      = ($EvaluationResults | Where-Object { $_.HealthState -eq "URGENT"   }).Count
        ExpiredCount     = ($EvaluationResults | Where-Object { $_.HealthState -eq "EXPIRED"  }).Count
        ActionRequired   = ($EvaluationResults | Where-Object { $_.ActionRequired -eq $true   }).Count
        OverallHealth    = if ($EvaluationResults | Where-Object { $_.HealthState -eq "URGENT"  }) { "URGENT"   }
                           elseif ($EvaluationResults | Where-Object { $_.HealthState -eq "EXPIRED"  }) { "EXPIRED"  }
                           elseif ($EvaluationResults | Where-Object { $_.HealthState -eq "CRITICAL" }) { "CRITICAL" }
                           elseif ($EvaluationResults | Where-Object { $_.HealthState -eq "WARNING"  }) { "WARNING"  }
                           else { "HEALTHY" }
    }

    # -------------------------------------------------------------------------
    # Serialize results (convert datetime to ISO strings for JSON)
    # -------------------------------------------------------------------------
    $SerializableResults = foreach ($Result in $EvaluationResults) {
        [PSCustomObject]@{
            ResourceType      = $Result.ResourceType
            ResourceId        = $Result.ResourceId
            DisplayName       = $Result.DisplayName
            DaysRemaining     = $Result.DaysRemaining
            HoursRemaining    = $Result.HoursRemaining
            ExpirationDate    = if ($Result.ExpirationDate) { $Result.ExpirationDate.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
            IsExpired         = $Result.IsExpired
            IsInRenewalWindow = $Result.IsInRenewalWindow
            RenewalWindowDays = $Result.RenewalWindowDays
            ExpirationPercent = $Result.ExpirationPercent
            TrendDirection    = $Result.TrendDirection
            HealthState       = $Result.HealthState
            HealthStateLabel  = $Result.HealthStateLabel
            HealthStateColor  = $Result.HealthStateColor
            HealthStateIcon   = $Result.HealthStateIcon
            Priority          = $Result.Priority
            ActionRequired    = $Result.ActionRequired
            AlertChannels     = $Result.AlertChannels
            Description       = $Result.Description
            EvaluatedAt       = if ($Result.EvaluatedAt) { $Result.EvaluatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
        }
    }

    # -------------------------------------------------------------------------
    # Build the full report object
    # -------------------------------------------------------------------------
    $Report = [PSCustomObject]@{
        reportVersion      = "1.0.0"
        platformName       = "Intune Expiry Monitoring Platform"
        generatedAt        = $ReportGeneratedAt
        summary            = $Summary
        resources          = $SerializableResults
    }

    # -------------------------------------------------------------------------
    # Ensure output directory exists
    # -------------------------------------------------------------------------
    $OutputDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        Write-Verbose "[Report] Created output directory: $OutputDirectory"
    }

    # -------------------------------------------------------------------------
    # Write JSON report
    # -------------------------------------------------------------------------
    try {
        $Report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "[Report] Report written to: $OutputPath"
        return $OutputPath
    }
    catch {
        Write-Error "[Report] Failed to write report to '$OutputPath': $($_.Exception.Message)"
        throw
    }
}
