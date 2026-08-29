<#
.SYNOPSIS
    Main orchestrator for the Intune Expiry Monitoring Platform.

.DESCRIPTION
    Coordinates all monitoring layers in sequence:

        1. Load configuration
        2. Authenticate with Microsoft Entra ID (OAuth 2.0)
        3. Discover Intune management resources (Microsoft Graph)
        4. Process raw Graph responses (JSON parsing + property extraction)
        5. Normalize resource data (unified schema)
        6. Calculate expiry metrics (DaysRemaining, RenewalWindow, etc.)
        7. Evaluate health states (Threshold evaluation)
        8. Export monitoring report (for dashboard consumption)
        9. Send alerts (Email / Teams / ServiceNow based on HealthState)

    End-to-End Flow:
        Microsoft Entra ID -> Graph API -> Raw JSON -> Processed Properties
            -> Normalized Data -> Metrics -> Evaluation -> Report + Alerts

.PARAMETER ConfigPath
    Path to monitoring_config.json. Defaults to '.\config\monitoring_config.json'.

.PARAMETER DryRun
    If specified, skips alert sending. Useful for testing without notifications.

.PARAMETER Verbose
    Enables verbose output for debugging.

.EXAMPLE
    # Normal monitoring run
    .\src\core\Invoke-MonitoringRun.ps1

    # Dry run (no alerts sent)
    .\src\core\Invoke-MonitoringRun.ps1 -DryRun

    # With verbose logging
    .\src\core\Invoke-MonitoringRun.ps1 -Verbose

.NOTES
    This script is the primary entry point for the monitoring platform.
    It can be run manually, via Windows Task Scheduler, or as an Azure Automation Runbook.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ".\config\monitoring_config.json",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# =============================================================================
# INITIALIZATION
# =============================================================================

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptRoot)

Set-Location $ProjectRoot

# Dot-source all modules
. "$ProjectRoot\src\auth\Get-GraphToken.ps1"
. "$ProjectRoot\src\collectors\Get-APNSCertificate.ps1"
. "$ProjectRoot\src\collectors\Get-DEPTokens.ps1"
. "$ProjectRoot\src\collectors\Get-VPPTokens.ps1"
. "$ProjectRoot\src\processors\Invoke-ResourceProcessor.ps1"
. "$ProjectRoot\src\processors\Normalize-ResourceData.ps1"
. "$ProjectRoot\src\metrics\Calculate-ExpiryMetrics.ps1"
. "$ProjectRoot\src\evaluation\Invoke-ThresholdEvaluation.ps1"
. "$ProjectRoot\src\core\Write-MonitoringLog.ps1"
. "$ProjectRoot\src\core\Export-MonitoringReport.ps1"
. "$ProjectRoot\src\alerting\Send-EmailAlert.ps1"
. "$ProjectRoot\src\alerting\Send-TeamsAlert.ps1"
. "$ProjectRoot\src\alerting\Send-ServiceNowAlert.ps1"

# =============================================================================
# BANNER
# =============================================================================
Write-Host ""
Write-Host "  ==========================================================" -ForegroundColor Cyan
Write-Host "      Microsoft Intune Expiry Monitoring Platform           " -ForegroundColor Cyan
Write-Host "      Resource -> Property -> Metric -> Threshold -> Alert  " -ForegroundColor Cyan
Write-Host "  ==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Run started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Write-Host "  Config      : $ConfigPath"
Write-Host "  Dry Run     : $($DryRun.IsPresent)"
Write-Host ""

Write-MonitoringLog -Level "INFO" -Message "Monitoring run started." -Component "Orchestrator"

# =============================================================================
# STEP 1: LOAD CONFIGURATION
# =============================================================================
Write-Host "  [1/9] Loading configuration..." -ForegroundColor DarkGray

if (-not (Test-Path $ConfigPath)) {
    Write-MonitoringLog -Level "ERROR" -Message "Configuration file not found: $ConfigPath" -Component "Orchestrator"
    throw "Configuration file not found: $ConfigPath"
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    Write-MonitoringLog -Level "INFO" -Message "Configuration loaded successfully." -Component "Orchestrator"
}
catch {
    Write-MonitoringLog -Level "ERROR" -Message "Failed to parse configuration: $($_.Exception.Message)" -Component "Orchestrator"
    throw
}

$EnabledResources = $Config.monitoring.enabledResources
Write-Host "  Enabled resources: $($EnabledResources -join ', ')" -ForegroundColor DarkGray

# =============================================================================
# STEP 2: AUTHENTICATE
# =============================================================================
Write-Host ""
Write-Host "  [2/9] Authenticating with Microsoft Entra ID..." -ForegroundColor DarkGray

try {
    $Token = Get-GraphToken `
        -TenantId     $Config.authentication.tenantId `
        -ClientId     $Config.authentication.clientId `
        -ClientSecret $Config.authentication.clientSecret

    Write-Host "  [OK] Access token acquired. Expires at: $($Token.ExpiresAt.ToString('HH:mm:ss')) UTC" -ForegroundColor Green
    Write-MonitoringLog -Level "INFO" -Message "Access token acquired. Expires: $($Token.ExpiresAt)" -Component "Auth"
}
catch {
    Write-MonitoringLog -Level "ERROR" -Message "Authentication failed: $($_.Exception.Message)" -Component "Auth"
    throw
}

# =============================================================================
# STEPS 3-7: COLLECT, PROCESS, EVALUATE PER RESOURCE
# =============================================================================
$AllEvaluationResults = @()
$AlertQueue           = @()

foreach ($ResourceType in $EnabledResources) {

    Write-Host ""
    Write-Host "  ---------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Processing resource: $ResourceType" -ForegroundColor White
    Write-Host "  ---------------------------------------------------------" -ForegroundColor DarkGray

    try {
        # -------------------------------------------------------------------
        # STEP 3: DATA COLLECTION
        # -------------------------------------------------------------------
        Write-Host "  [3/9] Collecting resource from Microsoft Graph..." -ForegroundColor DarkGray

        $RawResources = switch ($ResourceType) {
            "APNsCertificate" {
                $Resource = Get-APNSCertificate -AccessToken $Token.AccessToken -GraphBaseUrl $Config.authentication.graphBaseUrl
                if ($null -ne $Resource) { @($Resource) } else { @() }
            }
            "DEPTokens" {
                Get-DEPTokens -AccessToken $Token.AccessToken -GraphBaseUrl $Config.authentication.graphBaseUrl
            }
            "VPPTokens" {
                Get-VPPTokens -AccessToken $Token.AccessToken -GraphBaseUrl $Config.authentication.graphBaseUrl
            }
            default {
                Write-Warning "  Unknown resource type: $ResourceType"
                @()
            }
        }

        if ($RawResources.Count -eq 0) {
            Write-Warning "  No resources found for $ResourceType."
            continue
        }

        Write-Host "  [OK] Retrieved $($RawResources.Count) resource(s)" -ForegroundColor Green

        foreach ($RawResource in $RawResources) {
            # -----------------------------------------------------------------
            # STEP 4: PROCESSING
            # -----------------------------------------------------------------
            Write-Host "  [4/9] Processing raw Graph response..." -ForegroundColor DarkGray
            $Extracted = Invoke-ResourceProcessor -RawResource $RawResource

            # -----------------------------------------------------------------
            # STEP 5: NORMALIZATION
            # -----------------------------------------------------------------
            Write-Host "  [5/9] Normalizing resource data..." -ForegroundColor DarkGray
            $Normalized = Normalize-ResourceData -ExtractedProperties $Extracted -RetrievedAt $RawResource.RetrievedAt

            # -----------------------------------------------------------------
            # STEP 6: METRICS CALCULATION
            # -----------------------------------------------------------------
            Write-Host "  [6/9] Calculating expiry metrics..." -ForegroundColor DarkGray
            $Metric = Calculate-ExpiryMetrics -NormalizedData $Normalized -ThresholdsConfigPath $Config.monitoring.thresholdsConfigPath

            # -----------------------------------------------------------------
            # STEP 7: THRESHOLD EVALUATION
            # -----------------------------------------------------------------
            Write-Host "  [7/9] Evaluating health state..." -ForegroundColor DarkGray
            $Evaluation = Invoke-ThresholdEvaluation -Metric $Metric -ThresholdsConfigPath $Config.monitoring.thresholdsConfigPath

            $AllEvaluationResults += $Evaluation

            Write-MonitoringLog -Level "INFO" `
                -Message "[$ResourceType] '$($Evaluation.DisplayName)' - $($Evaluation.HealthState) - $($Evaluation.DaysRemaining) days remaining." `
                -Component "Evaluation"

            # -----------------------------------------------------------------
            # Queue alerts for actionable health states
            # -----------------------------------------------------------------
            if ($Evaluation.HealthState -in $Config.alerting.alertOnHealthStates) {
                $AlertQueue += $Evaluation
            }
        }
    }
    catch {
        Write-MonitoringLog -Level "ERROR" -Message "Failed to process $ResourceType`: $($_.Exception.Message)" -Component "Orchestrator"
        Write-Warning "  [ERROR] Error processing $ResourceType`: $($_.Exception.Message)"
    }
}

# =============================================================================
# STEP 8: EXPORT REPORT
# =============================================================================
Write-Host ""
Write-Host "  [8/9] Exporting monitoring report..." -ForegroundColor DarkGray

try {
    $ReportPath = Export-MonitoringReport -EvaluationResults $AllEvaluationResults -OutputPath $Config.platform.reportOutputPath
    Write-Host "  [OK] Report exported: $ReportPath" -ForegroundColor Green
    Write-MonitoringLog -Level "INFO" -Message "Monitoring report exported to: $ReportPath" -Component "Orchestrator"
}
catch {
    Write-MonitoringLog -Level "ERROR" -Message "Failed to export report: $($_.Exception.Message)" -Component "Orchestrator"
    Write-Warning "  [ERROR] Report export failed: $($_.Exception.Message)"
}

# =============================================================================
# STEP 9: SEND ALERTS
# =============================================================================
Write-Host ""
Write-Host "  [9/9] Processing alert queue ($($AlertQueue.Count) alert(s))..." -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "  [DRY RUN] Alerts will NOT be sent." -ForegroundColor Yellow
}

foreach ($AlertItem in $AlertQueue) {
    Write-Host "  -> Alert: [$($AlertItem.HealthState)] $($AlertItem.DisplayName) - $($AlertItem.DaysRemaining) days" -ForegroundColor $(
        switch ($AlertItem.HealthState) {
            "URGENT"   { "Red"    }
            "CRITICAL" { "DarkYellow" }
            "WARNING"  { "Yellow" }
            default    { "Gray"   }
        }
    )

    if (-not $DryRun) {
        foreach ($Channel in $AlertItem.AlertChannels) {
            switch ($Channel) {
                "email" {
                    if ($Config.alerting.enableEmail) {
                        Send-EmailAlert -EvaluationResult $AlertItem -Config $Config
                    }
                }
                "teams" {
                    if ($Config.alerting.enableTeams) {
                        Send-TeamsAlert -EvaluationResult $AlertItem -WebhookUrl $Config.alerting.teamsWebhookUrl
                    }
                }
                "servicenow" {
                    if ($Config.alerting.enableServiceNow) {
                        Send-ServiceNowAlert -EvaluationResult $AlertItem -Config $Config
                    }
                }
            }
        }
    }
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "  ==========================================================" -ForegroundColor Cyan
Write-Host "  MONITORING RUN COMPLETE" -ForegroundColor Cyan
Write-Host "  ==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Resources evaluated : $($AllEvaluationResults.Count)"
Write-Host "  Alerts triggered    : $($AlertQueue.Count)"
Write-Host "  Completed at        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Write-Host ""

# Print health state summary
$HealthSummary = $AllEvaluationResults | Group-Object HealthState
foreach ($Group in $HealthSummary) {
    $Color = switch ($Group.Name) {
        "HEALTHY"  { "Green"       }
        "WARNING"  { "Yellow"      }
        "CRITICAL" { "DarkYellow"  }
        "URGENT"   { "Red"         }
        "EXPIRED"  { "DarkRed"     }
        default    { "Gray"        }
    }
    Write-Host "    $($Group.Name.PadRight(10)) : $($Group.Count)" -ForegroundColor $Color
}

Write-Host ""

Write-MonitoringLog -Level "INFO" -Message "Monitoring run completed. Resources: $($AllEvaluationResults.Count). Alerts: $($AlertQueue.Count)." -Component "Orchestrator"
