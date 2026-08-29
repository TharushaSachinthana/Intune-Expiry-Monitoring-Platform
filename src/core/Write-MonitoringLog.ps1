<#
.SYNOPSIS
    Structured logging module for the Intune Expiry Monitoring Platform.

.DESCRIPTION
    Provides consistent, timestamped log output for all monitoring components.
    Writes to both the console (with color coding) and a persistent log file.

.PARAMETER Level
    Log level: INFO, WARN, ERROR, DEBUG.

.PARAMETER Message
    The log message.

.PARAMETER Component
    The monitoring component generating the log entry (e.g., "Auth", "Collector", "Metrics").

.PARAMETER LogPath
    Directory path for log files. Defaults to '.\logs'.
#>

function Write-MonitoringLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$Component = "Platform",

        [Parameter(Mandatory = $false)]
        [string]$LogPath = ".\logs"
    )

    $Timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $LogFileName = "monitoring_$(Get-Date -Format 'yyyy-MM-dd').log"
    $LogEntry    = "[$Timestamp] [$Level] [$Component] $Message"

    # -------------------------------------------------------------------------
    # Console output with color coding
    # -------------------------------------------------------------------------
    $ConsoleColor = switch ($Level) {
        "INFO"  { "Cyan"    }
        "WARN"  { "Yellow"  }
        "ERROR" { "Red"     }
        "DEBUG" { "Gray"    }
        default { "White"   }
    }

    Write-Verbose $LogEntry
    if ($Level -eq "ERROR" -or $Level -eq "WARN") {
        Write-Host "  $LogEntry" -ForegroundColor $ConsoleColor
    }

    # -------------------------------------------------------------------------
    # Write to log file
    # -------------------------------------------------------------------------
    try {
        if (-not (Test-Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        $LogFilePath = Join-Path $LogPath $LogFileName
        Add-Content -Path $LogFilePath -Value $LogEntry -ErrorAction SilentlyContinue
    }
    catch {
        # Non-fatal: log file write failure should not stop monitoring
        Write-Verbose "Failed to write to log file: $($_.Exception.Message)"
    }
}
