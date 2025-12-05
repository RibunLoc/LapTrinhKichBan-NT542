param(
    [string]$EnvTag = "env:demo"
)

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ReportDir = Join-Path $Root "reports"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $ReportDir, $LogDir | Out-Null
$LogFile = Join-Path $LogDir "cis_droplet_ps.log"

function Write-Log {
    param([string]$Level = "INFO", [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "s"), $Level, $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

function Invoke-DoctlJson {
    param([string]$Args)
    $cmd = "doctl $Args --output json"
    Write-Log -Message "Running: $cmd"
    $result = & $env:COMSPEC /c $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Level "ERROR" -Message "doctl error: $result"
        throw "doctl failed"
    }
    return $result | ConvertFrom-Json
}

try {
    $droplets = Invoke-DoctlJson -Args "compute droplet list"
    $target = $droplets | Where-Object { $_.tags -contains $EnvTag }

    if (-not $target) {
        Write-Log -Level "ERROR" -Message "No droplet found with tag $EnvTag"
        exit 1
    }

    $failed = @()
    foreach ($d in $target) {
        if (-not ($d.features -contains "backups")) {
            Write-Log -Level "ERROR" -Message "Droplet $($d.name) missing backups"
            $failed += @{ control = "2.1.1"; droplet = $d.name; reason = "Backups disabled" }
        }
        if (-not ($d.features -contains "monitoring")) {
            Write-Log -Level "ERROR" -Message "Droplet $($d.name) missing monitoring"
            $failed += @{ control = "2.1.x"; droplet = $d.name; reason = "Monitoring not enabled" }
        }
    }

    $report = @{
        Timestamp = (Get-Date).ToString("s")
        EnvTag    = $EnvTag
        Failed    = $failed
    }

    $reportPath = Join-Path $ReportDir ("cis_droplet_{0:yyyyMMddHHmmss}.json" -f (Get-Date))
    ($report | ConvertTo-Json -Depth 6) | Out-File -FilePath $reportPath -Encoding utf8
    Write-Log -Message "Report written to $reportPath"

    if ($failed.Count -gt 0) {
        exit 1
    }
    exit 0
}
catch {
    Write-Log -Level "ERROR" -Message $_
    exit 2
}
