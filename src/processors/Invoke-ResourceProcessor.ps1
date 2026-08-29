<#
.SYNOPSIS
    Parses a raw Microsoft Graph API response and extracts relevant monitoring properties.

.DESCRIPTION
    The Processing Layer converts raw Graph JSON responses into structured property objects
    suitable for metric generation.

    This function handles multiple resource types and extracts the relevant expiration
    property for each resource type, as defined in the resource config files.

    Processing Flow:
        Graph API Response
               ↓
        JSON Parsing
               ↓
        Relevant Resource Properties
               ↓
        Expiration Information
               ↓
        Normalized Monitoring Data (for Normalize-ResourceData.ps1)

.PARAMETER RawResource
    The PSCustomObject returned by a collector (Get-APNSCertificate, Get-DEPTokens, etc.).
    Must have ResourceType and RawGraphResponse properties.

.OUTPUTS
    PSCustomObject with extracted properties relevant to expiry monitoring.

.EXAMPLE
    $Raw       = Get-APNSCertificate -AccessToken $Token.AccessToken
    $Processed = Invoke-ResourceProcessor -RawResource $Raw
#>

function Invoke-ResourceProcessor {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$RawResource
    )

    if ($null -eq $RawResource) {
        Write-Warning "[Processor] Received null resource. Skipping processing."
        return $null
    }

    $ResourceType = $RawResource.ResourceType
    $GraphData    = $RawResource.RawGraphResponse

    Write-Verbose "[Processor] Processing resource type: $ResourceType"

    # -------------------------------------------------------------------------
    # Resource-specific property extraction
    # Each resource type has a defined expiry property from the Graph response
    # -------------------------------------------------------------------------
    switch ($ResourceType) {

        "APNsCertificate" {
            Write-Verbose "[Processor:APNs] Extracting APNs certificate properties..."

            $ExpirationRaw = $GraphData.expirationDateTime
            $DisplayName   = if ($GraphData.appleIdentifier) { $GraphData.appleIdentifier } else { "APNs Certificate" }
            $ResourceId    = if ($GraphData.id)              { $GraphData.id }              else { [System.Guid]::NewGuid().ToString() }

            $ExtractedProperties = [PSCustomObject]@{
                ResourceType            = "APNsCertificate"
                ResourceId              = $ResourceId
                DisplayName             = $DisplayName
                ExpirationDateRaw       = $ExpirationRaw
                TopicIdentifier         = $GraphData.topicIdentifier
                LastModifiedDateRaw     = $GraphData.lastModifiedDateTime
                CertificateUploadStatus = $GraphData.certificateUploadStatus
                CertificateSerialNumber = $GraphData.certificateSerialNumber
                AdditionalProperties    = @{}
            }
        }

        "DEPToken" {
            Write-Verbose "[Processor:DEP] Extracting DEP token properties..."

            $ExpirationRaw = $GraphData.tokenExpirationDateTime
            $DisplayName   = if ($GraphData.tokenName)  { $GraphData.tokenName }  else { "DEP Token" }
            $ResourceId    = if ($GraphData.id)          { $GraphData.id }         else { [System.Guid]::NewGuid().ToString() }

            $ExtractedProperties = [PSCustomObject]@{
                ResourceType         = "DEPToken"
                ResourceId           = $ResourceId
                DisplayName          = $DisplayName
                ExpirationDateRaw    = $ExpirationRaw
                AppleIdentifier      = $GraphData.appleIdentifier
                LastModifiedDateRaw  = $GraphData.lastModifiedDateTime
                AdditionalProperties = @{ TokenType = $GraphData.enrollmentType }
            }
        }

        "VPPToken" {
            Write-Verbose "[Processor:VPP] Extracting VPP token properties..."

            $ExpirationRaw = $GraphData.expirationDateTime
            $DisplayName   = if ($GraphData.organizationName) { $GraphData.organizationName } else { "VPP Token" }
            $ResourceId    = if ($GraphData.id)               { $GraphData.id }              else { [System.Guid]::NewGuid().ToString() }

            $ExtractedProperties = [PSCustomObject]@{
                ResourceType         = "VPPToken"
                ResourceId           = $ResourceId
                DisplayName          = $DisplayName
                ExpirationDateRaw    = $ExpirationRaw
                LastModifiedDateRaw  = $GraphData.lastModifiedDateTime
                TokenState           = $GraphData.state
                AdditionalProperties = @{ AppleId = $GraphData.appleId }
            }
        }

        default {
            Write-Warning "[Processor] Unknown resource type: '$ResourceType'. Cannot extract properties."
            return $null
        }
    }

    # -------------------------------------------------------------------------
    # Validate that an expiration date was extracted
    # -------------------------------------------------------------------------
    if ([string]::IsNullOrEmpty($ExtractedProperties.ExpirationDateRaw)) {
        Write-Warning "[Processor:$ResourceType] No expiration date found in Graph response. Resource may not have expiry information."
    }
    else {
        Write-Verbose "[Processor:$ResourceType] Expiration date extracted: $($ExtractedProperties.ExpirationDateRaw)"
    }

    return $ExtractedProperties
}
