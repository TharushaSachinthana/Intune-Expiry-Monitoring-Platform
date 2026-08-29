<#
.SYNOPSIS
    Normalizes resource properties extracted from Microsoft Graph into a unified schema.

.DESCRIPTION
    The Normalization Layer ensures that regardless of the source resource type
    (APNs, DEP, VPP, etc.), the data output conforms to a strict, common schema
    expected by the Metrics Layer.

    Unified Schema:
        - ResourceType     (string)
        - ResourceId       (string)
        - DisplayName      (string)
        - ExpirationDate   (datetime)
        - LastModifiedDate (datetime)
        - RetrievedAt      (datetime)
        - AdditionalProperties (hashtable)
        - ProcessingErrors (array)
        - IsValid          (bool)

.PARAMETER ExtractedProperties
    The PSCustomObject output from Invoke-ResourceProcessor.ps1.

.PARAMETER RetrievedAt
    The timestamp when the raw resource was collected from Graph.

.OUTPUTS
    PSCustomObject - normalized resource data matching the unified schema.

.EXAMPLE
    $Extracted  = Invoke-ResourceProcessor -RawResource $Raw
    $Normalized = Normalize-ResourceData -ExtractedProperties $Extracted -RetrievedAt $Raw.RetrievedAt
#>

function Normalize-ResourceData {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$ExtractedProperties,

        [Parameter(Mandatory = $false)]
        [string]$RetrievedAt
    )

    $ProcessingErrors = @()

    Write-Verbose "[Normalizer] Normalizing resource: $($ExtractedProperties.ResourceType) - $($ExtractedProperties.DisplayName)"

    # -------------------------------------------------------------------------
    # Parse ExpirationDate
    # -------------------------------------------------------------------------
    $ExpirationDate = $null
    if (-not [string]::IsNullOrEmpty($ExtractedProperties.ExpirationDateRaw)) {
        try {
            $ExpirationDate = [datetime]::Parse($ExtractedProperties.ExpirationDateRaw).ToUniversalTime()
            Write-Verbose "[Normalizer] ExpirationDate parsed: $($ExpirationDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        }
        catch {
            $ErrorMessage = "Failed to parse ExpirationDate '$($ExtractedProperties.ExpirationDateRaw)': $($_.Exception.Message)"
            Write-Warning "[Normalizer] $ErrorMessage"
            $ProcessingErrors += $ErrorMessage
        }
    }
    else {
        $ErrorMessage = "ExpirationDate is null or empty. Resource cannot be evaluated for expiry."
        Write-Warning "[Normalizer] $ErrorMessage"
        $ProcessingErrors += $ErrorMessage
    }

    # -------------------------------------------------------------------------
    # Parse LastModifiedDate
    # -------------------------------------------------------------------------
    $LastModifiedDate = $null
    if (-not [string]::IsNullOrEmpty($ExtractedProperties.LastModifiedDateRaw)) {
        try {
            $LastModifiedDate = [datetime]::Parse($ExtractedProperties.LastModifiedDateRaw).ToUniversalTime()
        }
        catch {
            Write-Verbose "[Normalizer] Could not parse LastModifiedDate. Non-critical."
        }
    }

    # -------------------------------------------------------------------------
    # Parse RetrievedAt
    # -------------------------------------------------------------------------
    $RetrievedAtDate = $null
    if (-not [string]::IsNullOrEmpty($RetrievedAt)) {
        try {
            $RetrievedAtDate = [datetime]::Parse($RetrievedAt).ToUniversalTime()
        }
        catch {
            $RetrievedAtDate = (Get-Date).ToUniversalTime()
        }
    }
    else {
        $RetrievedAtDate = (Get-Date).ToUniversalTime()
    }

    # -------------------------------------------------------------------------
    # Build the normalized monitoring object
    # -------------------------------------------------------------------------
    $NormalizedData = [PSCustomObject]@{
        ResourceType         = $ExtractedProperties.ResourceType
        ResourceId           = $ExtractedProperties.ResourceId
        DisplayName          = $ExtractedProperties.DisplayName
        ExpirationDate       = $ExpirationDate
        LastModifiedDate     = $LastModifiedDate
        RetrievedAt          = $RetrievedAtDate
        AdditionalProperties = if ($ExtractedProperties.AdditionalProperties) { $ExtractedProperties.AdditionalProperties } else { @{} }
        ProcessingErrors     = $ProcessingErrors
        IsValid              = ($ProcessingErrors.Count -eq 0) -and ($null -ne $ExpirationDate)
    }

    if ($NormalizedData.IsValid) {
        Write-Verbose "[Normalizer] Normalization complete. Resource is valid for monitoring."
    }
    else {
        Write-Warning "[Normalizer] Resource has processing errors and may not be evaluatable."
    }

    return $NormalizedData
}
