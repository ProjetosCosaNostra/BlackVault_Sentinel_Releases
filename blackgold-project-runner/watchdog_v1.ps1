$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$LockPath = Join-Path $Base 'runner.lock'
$LogPath = Join-Path $Base 'watchdog.log'
$PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$MaxRunnerMinutes = 20

function Log([string]$Message) {
    $line = "$(Get-Date -Format o) $Message"
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-RunnerProcesses {
    $escaped = [regex]::Escape($RunnerPath)
    return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -and
            $_.CommandLine -match $escaped
        })
}

while ($true) {
    try {
        if (-not (Test-Path -LiteralPath $RunnerPath)) {
            Log "runner_missing=$RunnerPath"
            Start-Sleep -Seconds 15
            continue
        }

        $running = Get-RunnerProcesses
        foreach ($item in $running) {
            try {
                $proc = Get-Process -Id $item.ProcessId -ErrorAction Stop
                $age = (Get-Date) - $proc.StartTime
                if ($age.TotalMinutes -gt $MaxRunnerMinutes) {
                    Log "terminating_stale_runner pid=$($proc.Id) age_minutes=$([math]::Round($age.TotalMinutes,1))"
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Log "process_check_error=$($_.Exception.Message)"
            }
        }

        $running = Get-RunnerProcesses
        if ($running.Count -eq 0) {
            Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue

            $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $RunnerPath + '"'
            $child = Start-Process -FilePath $PowerShell -ArgumentList $args -WindowStyle Hidden -PassThru
            Log "runner_started pid=$($child.Id)"

            $deadline = (Get-Date).AddMinutes($MaxRunnerMinutes)
            while (-not $child.HasExited -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 2
                $child.Refresh()
            }

            if (-not $child.HasExited) {
                Log "runner_timeout pid=$($child.Id)"
                Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
            }
            else {
                Log "runner_exit pid=$($child.Id) code=$($child.ExitCode)"
            }
        }
    }
    catch {
        Log "watchdog_error=$($_.Exception.Message)"
    }

    Start-Sleep -Seconds 15
}
