[CmdletBinding()]
param(
    [string]$RegistrationToken = '',
    [string]$RunnerRoot = '',
    [string]$RunnerName = 'FELIPE-Junior-Resolve',
    [string]$RepositoryUrl = 'https://github.com/ProjetosCosaNostra/Junior_Resolve'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RunnerVersion = '2.337.0'
$PackageName = "actions-runner-win-x64-$RunnerVersion.zip"
$PackageUrl = "https://github.com/actions/runner/releases/download/v$RunnerVersion/$PackageName"
$ExpectedSha256 = '1150692afa94e71f872017e254ea55b6eece1eece3fe7e3a6d4c93d0a1b85cfc'
$TaskName = 'GitHub_Actions_Junior_Resolve'

if ([string]::IsNullOrWhiteSpace($RunnerRoot)) {
    $RunnerRoot = Join-Path $env:LOCALAPPDATA 'GitHubActionsRunner\Junior_Resolve'
}

function Get-RunnerTokenFromGitCredential {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { return $null }

    $previousInteractive = $env:GCM_INTERACTIVE
    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GCM_INTERACTIVE = 'Never'
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        $credentialInput = @('protocol=https','host=github.com','') -join [Environment]::NewLine
        $lines = @($credentialInput | & $git.Source credential fill 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }

        $credential = @{}
        foreach ($line in $lines) {
            $index = ([string]$line).IndexOf('=')
            if ($index -le 0) { continue }
            $credential[([string]$line).Substring(0,$index)] = ([string]$line).Substring($index + 1)
        }
        $secret = [string]$credential['password']
        if ([string]::IsNullOrWhiteSpace($secret)) { return $null }

        $headers = @{
            Authorization = "Bearer $secret"
            Accept = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent' = 'Junior-Resolve-UserTask-Runner-Installer'
        }
        $response = Invoke-RestMethod -Method POST -Uri 'https://api.github.com/repos/ProjetosCosaNostra/Junior_Resolve/actions/runners/registration-token' -Headers $headers -TimeoutSec 30
        return [string]$response.token
    }
    catch {
        return $null
    }
    finally {
        $env:GCM_INTERACTIVE = $previousInteractive
        $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }
}

function Resolve-RegistrationToken([string]$ExplicitToken) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitToken)) { return $ExplicitToken }

    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($gh) {
        try {
            & $gh.Source auth status 1>$null 2>$null
            if ($LASTEXITCODE -eq 0) {
                $json = & $gh.Source api --method POST repos/ProjetosCosaNostra/Junior_Resolve/actions/runners/registration-token
                if ($LASTEXITCODE -eq 0) {
                    $payload = $json | ConvertFrom-Json
                    if (-not [string]::IsNullOrWhiteSpace([string]$payload.token)) {
                        return [string]$payload.token
                    }
                }
            }
        }
        catch {}
    }
    return Get-RunnerTokenFromGitCredential
}

function Ensure-RunnerTask {
    param([string]$Root)

    Import-Module ScheduledTasks -ErrorAction Stop
    $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $runCmd = Join-Path $Root 'run.cmd'
    if (-not (Test-Path -LiteralPath $runCmd)) { throw "RUN_CMD_NOT_FOUND: $runCmd" }

    $arguments = '/d /s /c ""' + $runCmd + '""'
    $action = New-ScheduledTaskAction -Execute $cmd -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
}

New-Item -ItemType Directory -Force -Path $RunnerRoot | Out-Null
$installLog = Join-Path $RunnerRoot 'runner-user-task-install.log'
$installError = Join-Path $RunnerRoot 'runner-user-task-install-error.txt'
Remove-Item -LiteralPath $installError -Force -ErrorAction SilentlyContinue

try {
    Start-Transcript -Path $installLog -Append -Force | Out-Null
}
catch {}

try {
    $runnerConfig = Join-Path $RunnerRoot '.runner'
    if (-not (Test-Path -LiteralPath $runnerConfig)) {
        $token = Resolve-RegistrationToken $RegistrationToken
        if ([string]::IsNullOrWhiteSpace($token)) { throw 'RUNNER_REGISTRATION_TOKEN_REQUIRED' }

        Get-ChildItem -LiteralPath $RunnerRoot -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('runner-user-task-install.log','runner-user-task-install-error.txt') } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $zipPath = Join-Path $RunnerRoot $PackageName
        Invoke-WebRequest -UseBasicParsing -Uri $PackageUrl -OutFile $zipPath

        $actualSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -ne $ExpectedSha256) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            throw "RUNNER_PACKAGE_HASH_MISMATCH expected=$ExpectedSha256 actual=$actualSha256"
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $RunnerRoot -Force

        Push-Location $RunnerRoot
        try {
            & .\config.cmd --unattended --url $RepositoryUrl --token $token --name $RunnerName --labels 'junior-resolve,windows,x64' --work '_work' --replace
            if ($LASTEXITCODE -ne 0) { throw "RUNNER_CONFIG_FAILED_$LASTEXITCODE" }
        }
        finally {
            Pop-Location
        }
    }

    Ensure-RunnerTask -Root $RunnerRoot

    $receipt = [ordered]@{
        Schema = 1
        Project = 'Junior_Resolve'
        Runner = 'actions/runner'
        RunnerVersion = $RunnerVersion
        RunnerRoot = $RunnerRoot
        RunnerName = $RunnerName
        RepositoryUrl = $RepositoryUrl
        Labels = @('self-hosted','Windows','X64','junior-resolve')
        ScheduledTask = $TaskName
        InstalledAsService = $false
        InstalledAsUserTask = $true
        BridgeInstalled = $false
        ArbitraryRemoteShellAdded = $false
        StartedAt = (Get-Date).ToString('o')
    }
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $RunnerRoot 'junior-resolve-user-runner-receipt.json') -Encoding UTF8

    Write-Host ''
    Write-Host 'JUNIOR RESOLVE - GITHUB RUNNER OFICIAL EM USER TASK' -ForegroundColor Green
    Write-Host "Versao: $RunnerVersion"
    Write-Host "Pasta: $RunnerRoot"
    Write-Host "Task: $TaskName"
    Write-Host 'Labels: self-hosted, Windows, X64, junior-resolve'
    Write-Host 'Servico Windows: NAO'
    Write-Host 'Scheduled Task do usuario: SIM'
}
catch {
    $message = $_.Exception.Message
    $message | Set-Content -LiteralPath $installError -Encoding UTF8
    Write-Host ''
    Write-Host 'JUNIOR RESOLVE - RUNNER USER TASK NAO INSTALADO' -ForegroundColor Red
    Write-Host "Erro real: $message" -ForegroundColor Red
    Write-Host "Log: $installLog"
    Write-Host "Erro: $installError"
    throw "RUNNER_USER_TASK_INSTALL_FAILED: $message"
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
