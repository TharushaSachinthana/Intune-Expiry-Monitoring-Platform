<#
.SYNOPSIS
    Retrieves Apple Volume Purchase Program (VPP) tokens from Microsoft Intune via Microsoft Graph.

.DESCRIPTION
    Calls the Microsoft Graph endpoint to retrieve VPP tokens that authorize
    Intune to deploy apps purchased through Apple Business Manager.

    Graph Endpoint:
        GET /deviceAppManagement/vppTokens

    NOTE: This collector is part of Phase 8 (Future Scope).
          Set 'enabled: true' in config/resources/vpp_resource.json to activate.

.PARAMETER AccessToken
    A valid Microsoft Graph Bearer access token.

.PARAMETER GraphBaseUrl
    The Microsoft Graph base URL. Defaults to 'https://graph.microsoft.com/v1.0'.

.OUTPUTS
    Array of PSCustomObjects, one per VPP token found.

.NOTES
    Required Microsoft Graph Application Permission:
        DeviceManagementApps.Read.All
#>

function Get-VPPTokens {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [string]$GraphBaseUrl = "https://graph.microsoft.com/v1.0"
    )

    $Endpoint   = "/deviceAppManagement/vppTokens"
    $RequestUri = "$GraphBaseUrl$Endpoint"

    Write-Verbose "[Collector:VPP] Requesting VPP tokens from Graph: $RequestUri"

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
            Write-Warning "[Collector:VPP] No VPP tokens found."
            return @()
        }

        Write-Verbose "[Collector:VPP] Retrieved $($Tokens.Count) VPP token(s)."

        $RetrievedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        $Results = foreach ($Token in $Tokens) {
            [PSCustomObject]@{
                ResourceType     = "VPPToken"
                GraphEndpoint    = $Endpoint
                RetrievedAt      = $RetrievedAt
                RawGraphResponse = $Token
            }
        }

        return $Results
    }
    catch [System.Net.WebException] {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        Write-Error "[Collector:VPP] Graph API request failed with status: $StatusCode. Error: $($_.Exception.Message)"
        throw
    }
    catch {
        Write-Error "[Collector:VPP] Unexpected error: $($_.Exception.Message)"
        throw
    }
}
