<#
.SYNOPSIS
    Retrieves the Apple Push Notification Service (APNs) certificate from Microsoft Intune via Microsoft Graph.

.DESCRIPTION
    Calls the Microsoft Graph endpoint to retrieve the APNs certificate resource
    associated with the Intune tenant's Apple device management configuration.

    Graph Endpoint:
        GET /deviceManagement/applePushNotificationCertificate

    The APNs certificate enables Intune to communicate with Apple Push Notification
    Service for managing iOS, iPadOS, and macOS devices.

    Dependency Chain:
        APNs Certificate
               ↓
        Apple Push Notification Service
               ↓
        Intune Device Communication
               ↓
        Managed Apple Devices
               ↓
        Policy Delivery
               ↓
        Business Operations

.PARAMETER AccessToken
    A valid Microsoft Graph Bearer access token.
    Obtain using Get-GraphToken.ps1 with appropriate permissions.

.PARAMETER GraphBaseUrl
    The Microsoft Graph base URL. Defaults to 'https://graph.microsoft.com/v1.0'.

.OUTPUTS
    PSCustomObject containing the raw Graph API response for the APNs certificate.

.EXAMPLE
    $Token  = Get-GraphToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $APNs   = Get-APNSCertificate -AccessToken $Token.AccessToken

.NOTES
    Required Microsoft Graph Application Permission:
        DeviceManagementServiceConfig.Read.All

    Graph API Reference:
        https://docs.microsoft.com/en-us/graph/api/intune-devices-applepushnotificationcertificate-get
#>

function Get-APNSCertificate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [string]$GraphBaseUrl = "https://graph.microsoft.com/v1.0"
    )

    # -------------------------------------------------------------------------
    # Build the Graph API request URI
    # -------------------------------------------------------------------------
    $Endpoint = "/deviceManagement/applePushNotificationCertificate"
    $RequestUri = "$GraphBaseUrl$Endpoint"

    Write-Verbose "[Collector:APNs] Requesting resource from Graph: $RequestUri"

    # -------------------------------------------------------------------------
    # Build request headers with Bearer token
    # -------------------------------------------------------------------------
    $Headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }

    try {
        Write-Verbose "[Collector:APNs] Sending GET request..."

        $Response = Invoke-RestMethod `
            -Uri        $RequestUri `
            -Method     GET `
            -Headers    $Headers `
            -ErrorAction Stop

        Write-Verbose "[Collector:APNs] Resource retrieved successfully."

        # ---------------------------------------------------------------------
        # Attach metadata to the response for downstream processing
        # ---------------------------------------------------------------------
        $RawResource = [PSCustomObject]@{
            ResourceType       = "APNsCertificate"
            GraphEndpoint      = $Endpoint
            RetrievedAt        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            RawGraphResponse   = $Response
        }

        return $RawResource
    }
    catch [System.Net.WebException] {
        $StatusCode = $_.Exception.Response.StatusCode.value__

        switch ($StatusCode) {
            403 {
                Write-Error "[Collector:APNs] Access Denied (403). Verify the App Registration has 'DeviceManagementServiceConfig.Read.All' permission with admin consent."
            }
            404 {
                Write-Warning "[Collector:APNs] Resource not found (404). The tenant may not have an APNs certificate configured in Intune."
                return $null
            }
            401 {
                Write-Error "[Collector:APNs] Unauthorized (401). Access token may be expired or invalid."
            }
            default {
                Write-Error "[Collector:APNs] Graph API request failed with status: $StatusCode. Error: $($_.Exception.Message)"
            }
        }
        throw
    }
    catch {
        Write-Error "[Collector:APNs] Unexpected error retrieving APNs certificate: $($_.Exception.Message)"
        throw
    }
}
