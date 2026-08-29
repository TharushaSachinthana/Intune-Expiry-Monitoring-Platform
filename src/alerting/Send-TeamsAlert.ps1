<#
.SYNOPSIS
    Sends a Microsoft Teams Adaptive Card alert for an Intune resource expiry event.

.DESCRIPTION
    Posts an Adaptive Card notification to a Microsoft Teams channel via an Incoming Webhook connector.
    The card includes the resource name, health state, days remaining, expiration date, and action guidance.

.PARAMETER EvaluationResult
    The PSCustomObject output from Invoke-ThresholdEvaluation.ps1.

.PARAMETER WebhookUrl
    The Microsoft Teams Incoming Webhook URL.
    Configure at: Teams Channel → Connectors → Incoming Webhook.

.NOTES
    Phase 9 feature. Set enableTeams: true in monitoring_config.json to activate.
#>

function Send-TeamsAlert {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$EvaluationResult,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WebhookUrl
    )

    $ResourceName   = $EvaluationResult.DisplayName
    $HealthState    = $EvaluationResult.HealthState
    $HealthLabel    = $EvaluationResult.HealthStateLabel
    $DaysRemaining  = $EvaluationResult.DaysRemaining
    $ExpirationDate = if ($EvaluationResult.ExpirationDate) { $EvaluationResult.ExpirationDate.ToString("dd MMMM yyyy") } else { "Unknown" }
    $StateColor     = $EvaluationResult.HealthStateColor -replace "#", ""
    $Description    = $EvaluationResult.Description
    $ActionRequired = if ($EvaluationResult.ActionRequired) { "⚡ Yes — Immediate action required" } else { "No" }

    Write-Verbose "[Alert:Teams] Preparing Teams Adaptive Card for [$HealthState] $ResourceName"

    # -------------------------------------------------------------------------
    # Build Teams Adaptive Card payload
    # -------------------------------------------------------------------------
    $TeamsPayload = @{
        type        = "message"
        attachments = @(
            @{
                contentType = "application/vnd.microsoft.card.adaptive"
                content     = @{
                    '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
                    type    = "AdaptiveCard"
                    version = "1.4"
                    body    = @(
                        @{
                            type   = "Container"
                            style  = "emphasis"
                            items  = @(
                                @{
                                    type   = "TextBlock"
                                    text   = "🔔 Intune Expiry Monitoring Alert"
                                    weight = "Bolder"
                                    size   = "Medium"
                                    color  = "Accent"
                                },
                                @{
                                    type  = "TextBlock"
                                    text  = "$($EvaluationResult.HealthStateIcon) $HealthLabel — $ResourceName"
                                    size  = "Large"
                                    weight = "Bolder"
                                    wrap  = $true
                                }
                            )
                        },
                        @{
                            type  = "FactSet"
                            facts = @(
                                @{ title = "Resource";        value = $ResourceName },
                                @{ title = "Health State";    value = $HealthLabel },
                                @{ title = "Days Remaining";  value = "$DaysRemaining days" },
                                @{ title = "Expires On";      value = $ExpirationDate },
                                @{ title = "Action Required"; value = $ActionRequired },
                                @{ title = "Description";     value = $Description }
                            )
                        }
                    )
                    actions = @(
                        @{
                            type  = "Action.OpenUrl"
                            title = "Open Intune Admin Center"
                            url   = "https://intune.microsoft.com"
                        }
                    )
                }
            }
        )
    }

    # -------------------------------------------------------------------------
    # Send to Teams webhook
    # -------------------------------------------------------------------------
    try {
        $JsonPayload = $TeamsPayload | ConvertTo-Json -Depth 20

        $Response = Invoke-RestMethod `
            -Uri         $WebhookUrl `
            -Method      POST `
            -Body        $JsonPayload `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Host "  ✓ [Alert:Teams] Adaptive Card posted to Teams channel." -ForegroundColor Green
    }
    catch {
        Write-Error "[Alert:Teams] Failed to send Teams alert: $($_.Exception.Message)"
    }
}
