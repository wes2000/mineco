# MiningSim post-exit updater helper.
#
# Spawned by the running game just before it quits. Waits for the game's
# process to exit, copies the freshly extracted build over the install dir,
# and relaunches the game. Logs to %TEMP%\mineco_update_helper.log.

param(
    [Parameter(Mandatory=$true)][int]$WaitPid,
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Dest,
    [Parameter(Mandatory=$true)][string]$Exe
)

$ErrorActionPreference = 'Stop'
$LogPath = Join-Path $env:TEMP 'mineco_update_helper.log'

function Write-Log($msg) {
    $stamp = Get-Date -Format 's'
    Add-Content -Path $LogPath -Value "[$stamp] $msg"
}

try {
    Write-Log "Helper started. WaitPid=$WaitPid Source=$Source Dest=$Dest Exe=$Exe"

    # Wait for the game to exit (max 30s).
    $deadline = (Get-Date).AddSeconds(30)
    while (Get-Process -Id $WaitPid -ErrorAction SilentlyContinue) {
        if ((Get-Date) -gt $deadline) {
            Write-Log "Timeout waiting for pid $WaitPid to exit."
            exit 1
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Log "Game exited."

    # Brief grace period for file handles to release.
    Start-Sleep -Milliseconds 500

    if (-not (Test-Path $Source)) {
        Write-Log "Source directory missing: $Source"
        exit 1
    }
    if (-not (Test-Path $Dest)) {
        Write-Log "Dest directory missing: $Dest"
        exit 1
    }

    # Copy new files over the install directory. -Force overwrites; -Recurse
    # walks subdirs.
    Copy-Item -Path (Join-Path $Source '*') -Destination $Dest -Recurse -Force
    Write-Log "Copy complete."

    # Relaunch the game.
    Start-Process -FilePath $Exe -WorkingDirectory $Dest
    Write-Log "Relaunched $Exe."

    # Best-effort cleanup of the staging dir.
    try {
        Remove-Item -Path (Split-Path $Source -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Cleanup skipped: $($_.Exception.Message)"
    }
}
catch {
    Write-Log "Helper failed: $($_.Exception.Message)"
    exit 1
}
