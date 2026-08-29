<#
.SYNOPSIS
    Sends a rich HTML email alert for an Intune resource expiry event.

.DESCRIPTION
    Generates and sends an HTML email notification when a monitored resource
    reaches a WARNING, CRITICAL, or URGENT health state.

    Supports two sending modes:
        1. SMTP (Office 365 or on-premises)
        2. Microsoft Graph sendMail API (modern, token-based)

.PARAMETER EvaluationResult
    The PSCustomObject output from Invoke-ThresholdEvaluation.ps1.

.PARAMETER Config
    The full monitoring configuration object loaded from monitoring_config.json.
#>

function Send-EmailAlert {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$EvaluationResult,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$Config
    )

    $ResourceName   = $EvaluationResult.DisplayName
    $HealthState    = $EvaluationResult.HealthState
    $DaysRemaining  = $EvaluationResult.DaysRemaining
    $ExpirationDate = if ($EvaluationResult.ExpirationDate) { $EvaluationResult.ExpirationDate.ToString("dd MMMM yyyy") } else { "Unknown" }
    $StateColor     = $EvaluationResult.HealthStateColor
    $StateIcon      = $EvaluationResult.HealthStateIcon

    Write-Verbose "[Alert:Email] Preparing email for [$HealthState] $ResourceName"

    # -------------------------------------------------------------------------
    # Build HTML email body
    # -------------------------------------------------------------------------
    $TemplatePath = ".\src\alerting\templates\email_template.html"
    if (Test-Path $TemplatePath) {
        $EmailBody = Get-Content $TemplatePath -Raw
        $EmailBody = $EmailBody `
            -replace "{{RESOURCE_NAME}}",   $ResourceName `
            -replace "{{HEALTH_STATE}}",    $HealthState `
            -replace "{{HEALTH_LABEL}}",    $EvaluationResult.HealthStateLabel `
            -replace "{{STATE_COLOR}}",     $StateColor `
            -replace "{{STATE_ICON}}",      $StateIcon `
            -replace "{{DAYS_REMAINING}}",  $DaysRemaining `
            -replace "{{EXPIRATION_DATE}}", $ExpirationDate `
            -replace "{{DESCRIPTION}}",     $EvaluationResult.Description `
            -replace "{{GENERATED_AT}}",    (Get-Date -Format "dd MMM yyyy HH:mm UTC")
    }
    else {
        # Fallback plain-text body
        $EmailBody = @"
<html><body>
<h2>$StateIcon Intune Expiry Alert: $HealthState</h2>
<p><strong>Resource:</strong> $ResourceName</p>
<p><strong>Health State:</strong> $HealthState</p>
<p><strong>Days Remaining:</strong> $DaysRemaining</p>
<p><strong>Expiration Date:</strong> $ExpirationDate</p>
<p><strong>Action:</strong> $($EvaluationResult.Description)</p>
</body></html>
"@
    }

    $Subject = "$StateIcon [$HealthState] Intune Expiry Alert: $ResourceName — $DaysRemaining days remaining"

    # -------------------------------------------------------------------------
    # Send via SMTP or Graph sendMail
    # -------------------------------------------------------------------------
    try {
        if ($Config.alerting.email.useGraphSendMail) {
            # Microsoft Graph sendMail
            Write-Verbose "[Alert:Email] Sending via Microsoft Graph sendMail..."
            # Graph sendMail implementation placeholder (requires delegated or app send permission)
            Write-Warning "[Alert:Email] Graph sendMail not yet implemented. Configure SMTP or implement Graph sendMail."
        }
        else {
            # SMTP
            $SmtpServer    = $Config.alerting.email.smtpServer
            $SmtpPort      = $Config.alerting.email.smtpPort
            $Sender        = $Config.alerting.email.senderAddress
            $Recipients    = $Config.alerting.email.recipientAddresses

            Send-MailMessage `
                -SmtpServer $SmtpServer `
                -Port       $SmtpPort `
                -From       $Sender `
                -To         $Recipients `
                -Subject    $Subject `
                -Body       $EmailBody `
                -BodyAsHtml `
                -UseSsl     `
                -ErrorAction Stop

            Write-Host "  ✓ [Alert:Email] Email sent to: $($Recipients -join ', ')" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "[Alert:Email] Failed to send email alert: $($_.Exception.Message)"
    }
}
