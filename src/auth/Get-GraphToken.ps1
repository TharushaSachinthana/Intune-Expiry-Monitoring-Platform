<#
.SYNOPSIS
    Obtains a Microsoft Graph API access token using the OAuth 2.0 Client Credentials Flow.

.DESCRIPTION
    Authenticates the monitoring platform as a Microsoft Entra ID application identity.
    Uses the Client Credentials Flow — no user interaction required.
    Suitable for unattended automation and Azure Automation runbooks.

    Authentication Flow:
        Monitoring Application
               ↓ Client Credentials (ClientId + ClientSecret)
        Microsoft Entra ID
               ↓ Access Token (JWT Bearer)
        Microsoft Graph API
               ↓ Authorized Resource Request
        Intune Management Resources

.PARAMETER TenantId
    The Microsoft Entra ID Tenant ID (Directory ID).

.PARAMETER ClientId
    The Application (client) ID of the Entra ID App Registration.

.PARAMETER ClientSecret
    The client secret associated with the App Registration.
    Use a SecureString or retrieve from Azure Key Vault in production.

.PARAMETER Scope
    The OAuth 2.0 scope. Defaults to 'https://graph.microsoft.com/.default'
    which uses all permissions granted to the application.

.OUTPUTS
    PSCustomObject with properties:
        - AccessToken   [string]  : The Bearer token for Graph API requests
        - TokenType     [string]  : Always "Bearer"
        - ExpiresIn     [int]     : Token lifetime in seconds (typically 3600)
        - AcquiredAt    [datetime]: Timestamp when the token was acquired
        - ExpiresAt     [datetime]: Calculated token expiry time

.EXAMPLE
    $Token = Get-GraphToken -TenantId "your-tenant-id" `
                            -ClientId  "your-client-id" `
                            -ClientSecret "your-secret"

.NOTES
    Required Entra ID App Registration permissions:
        - DeviceManagementServiceConfig.Read.All  (APNs, DEP monitoring)
        - DeviceManagementApps.Read.All           (VPP token monitoring)
        - DeviceManagementConfiguration.Read.All  (Enrollment token monitoring)

    Least Privilege Principle:
        Grant only the permissions required for the specific resources being monitored.

    References:
        Microsoft identity platform — Client Credentials Flow:
        https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
#>

function Get-GraphToken {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [string]$Scope = "https://graph.microsoft.com/.default"
    )

    # -------------------------------------------------------------------------
    # Build the token endpoint URL
    # Format: https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token
    # -------------------------------------------------------------------------
    $TokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    Write-Verbose "[Auth] Requesting access token from: $TokenEndpoint"
    Write-Verbose "[Auth] Client ID: $ClientId"
    Write-Verbose "[Auth] Scope: $Scope"

    # -------------------------------------------------------------------------
    # Construct the OAuth 2.0 Client Credentials request body
    # grant_type = client_credentials (application identity, no user context)
    # -------------------------------------------------------------------------
    $RequestBody = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
    }

    try {
        Write-Verbose "[Auth] Sending token request to Microsoft Entra ID..."

        $AcquiredAt = Get-Date

        # ---------------------------------------------------------------------
        # POST request to the Entra ID token endpoint
        # ---------------------------------------------------------------------
        $TokenResponse = Invoke-RestMethod `
            -Uri         $TokenEndpoint `
            -Method      POST `
            -ContentType "application/x-www-form-urlencoded" `
            -Body        $RequestBody `
            -ErrorAction Stop

        # Validate the response contains an access token
        if ([string]::IsNullOrEmpty($TokenResponse.access_token)) {
            throw "Token response received but access_token property is null or empty."
        }

        $ExpiresAt = $AcquiredAt.AddSeconds($TokenResponse.expires_in)

        Write-Verbose "[Auth] Access token acquired successfully."
        Write-Verbose "[Auth] Token type: $($TokenResponse.token_type)"
        Write-Verbose "[Auth] Token expires in: $($TokenResponse.expires_in) seconds"
        Write-Verbose "[Auth] Token expires at: $($ExpiresAt.ToString('yyyy-MM-ddTHH:mm:ssZ'))"

        # ---------------------------------------------------------------------
        # Return a structured token object
        # ---------------------------------------------------------------------
        return [PSCustomObject]@{
            AccessToken  = $TokenResponse.access_token
            TokenType    = $TokenResponse.token_type
            ExpiresIn    = $TokenResponse.expires_in
            AcquiredAt   = $AcquiredAt
            ExpiresAt    = $ExpiresAt
            TenantId     = $TenantId
            ClientId     = $ClientId
        }
    }
    catch [System.Net.WebException] {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        $ErrorMessage = $_.Exception.Message

        Write-Error "[Auth] HTTP error acquiring token. Status: $StatusCode. Error: $ErrorMessage"

        if ($StatusCode -eq 400) {
            Write-Error "[Auth] Bad Request — Check TenantId, ClientId, and ClientSecret values."
        }
        elseif ($StatusCode -eq 401) {
            Write-Error "[Auth] Unauthorized — Client Secret may be incorrect or expired."
        }
        throw
    }
    catch {
        Write-Error "[Auth] Unexpected error acquiring access token: $($_.Exception.Message)"
        throw
    }
}
