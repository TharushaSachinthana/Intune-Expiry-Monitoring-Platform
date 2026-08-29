<#
.SYNOPSIS
    Retrieves Apple Device Enrollment Program (DEP / ABM) tokens from Microsoft Intune via Microsoft Graph.

.DESCRIPTION
    Calls the Microsoft Graph endpoint to retrieve DEP onboarding settings,
    which represent DEP/Apple Business Manager token integrations configured in Intune.

    Graph Endpoint:
        GET /deviceManagement/depOnboardingSettings

    NOTE: This collector is part of Phase 8 (Future Scope).
          Set 'enabled: true' in config/resources/dep_resource.json to activate.

.PARAMETER AccessToken
    A valid Microsoft Graph Bearer access token.

.PARAMETER GraphBaseUrl
    The Microsoft Graph base URL. Defaults to 'https://graph.microsoft.com/v1.0'.

.OUTPUTS
    Array of PSCustomObjects, one per DEP token found.

.NOTES
    Required Microsoft Graph Application Permission:
        DeviceManagementServiceConfig.Read.All
#>

function Get-DEPTokens {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [string]$GraphBaseUrl = "https://graph.microsoft.com/v1.0"
    )

    $Endpoint   = "/deviceManagement/depOnboardingSettings"
    $RequestUri = "$GraphBaseUrl$Endpoint"

    Write-Verbose "[Collector:DEP] Requesting DEP tokens from Graph: $RequestUri"

    $Headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }

    try {
        $Response = Invoke-RestMethod `
            -Uri        $RequestUri `
            -Method     GET `
            -Headers    $Headers `
            -ErrorAction Stop

        $Tokens = $Response.value

        if ($null -eq $Tokens -or $Tokens.Count -eq 0) {
            Write-Warning "[Collector:DEP] No DEP tokens found. The tenant may not have DEP configured."
            return @()
        }

        Write-Verbose "[Collector:DEP] Retrieved $($Tokens.Count) DEP token(s)."

        $RetrievedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        $Results = foreach ($Token in $Tokens) {
            [PSCustomObject]@{
                ResourceType     = "DEPToken"
                GraphEndpoint    = $Endpoint
                RetrievedAt      = $RetrievedAt
                RawGraphResponse = $Token
            }
        }

        return $Results
    }
    catch [System.Net.WebException] {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        Write-Error "[Collector:DEP] Graph API request failed with status: $StatusCode. Error: $($_.Exception.Message)"
        throw
    }
    catch {
        Write-Error "[Collector:DEP] Unexpected error: $($_.Exception.Message)"
        throw
    }
}
