$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_1_3.new.ps1'
$ConfigPath = Join-Path $Base 'projects.json'
$WorkersDir = Join-Path $Base 'workers'
$WorkerLogsDir = Join-Path $Base 'worker-launch-logs'
$LegacyTask = 'BlackGold_Project_Runner_V1'
$Branch = 'blackgold-project-runner-v1'
$RemoteUrl = 'https://github.com/ProjetosCosaNostra/BlackVault_Sentinel.git'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/82a949d45f06d5f2fe9129817208f01ae664d916/blackgold-project-runner/runner_v1_1_3.ps1'
$git = (Get-Command git.exe -ErrorAction Stop).Source

New-Item -ItemType Directory -Force -Path $Base,$WorkersDir,$WorkerLogsDir | Out-Null
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw 'PROJECT_CONFIG_NOT_FOUND' }

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'RUNNER_DOWNLOAD_FAILED' }
$runnerText = Get-Content -LiteralPath $TempPath -Raw
if ($runnerText -notmatch "RunnerVersion\s*=\s*'1\.1\.3'") { throw 'RUNNER_VERSION_MISMATCH' }

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $messages = ($errors | ForEach-Object { $_.Message }) -join ' | '
    throw ('RUNNER_PARSE_FAILED: ' + $messages)
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$projects = @($config.projects)
if ($projects.Count -lt 1) { throw 'NO_REGISTERED_PROJECTS' }

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $RunnerPath) {
    $backupPath = Join-Path $Base ('runner.before-v1_1_3.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ps1')
    Copy-Item -LiteralPath $RunnerPath -Destination $backupPath -Force
}
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

$seedControl = Join-Path $Base 'control'
if (-not (Test-Path -LiteralPath (Join-Path $seedControl '.git'))) {
    throw 'SEED_CONTROL_REPO_NOT_FOUND'
}

$oldGitTerminalPrompt = $env:GIT_TERMINAL_PROMPT
$oldGcmInteractive = $env:GCM_INTERACTIVE
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

try {
    foreach ($project in $projects) {
        $id = [string]$project.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $controlDir = Join-Path $Base ('control-' + $id)
        if (-not (Test-Path -LiteralPath (Join-Path $controlDir '.git'))) {
            if (Test-Path -LiteralPath $controlDir) { Remove-Item -LiteralPath $controlDir -Recurse -Force -ErrorAction SilentlyContinue }
            & $git clone --branch $Branch --single-branch $seedControl $controlDir | Out-Null
            if ($LASTEXITCODE -ne 0) { throw ('LOCAL_CONTROL_CLONE_FAILED: ' + $id) }
        }
        & $git -C $controlDir remote set-url origin $RemoteUrl | Out-Null
        & $git -C $controlDir config core.longpaths true | Out-Null
        & $git -C $controlDir checkout $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ('CONTROL_CHECKOUT_FAILED: ' + $id) }
    }
}
finally {
    $env:GIT_TERMINAL_PROMPT = $oldGitTerminalPrompt
    $env:GCM_INTERACTIVE = $oldGcmInteractive
}

$taskNames = @()
foreach ($project in $projects) {
    $id = [string]$project.id
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $safe = $id -replace '[^A-Za-z0-9_-]','_'
    $workerPath = Join-Path $WorkersDir ($safe + '.ps1')
    $workerLog = Join-Path $WorkerLogsDir ($safe + '.log')
    $taskName = 'BlackGold_Project_Runner_' + $safe

    $worker = @(
        '$ErrorActionPreference = ''Stop'''
        ('$env:BLACKGOLD_PROJECT_FILTER = ''' + $id + '''')
        '$env:GIT_TERMINAL_PROMPT = ''0'''
        '$env:GCM_INTERACTIVE = ''Never'''
        ('& ''' + $PowerShellExe + ''' -NoProfile -ExecutionPolicy Bypass -File ''' + $RunnerPath + ''' *>> ''' + $workerLog + '''')
        'exit $LASTEXITCODE'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($workerPath,$worker,[Text.UTF8Encoding]::new($false))

    $workerTokens = $null
    $workerErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($workerPath,[ref]$workerTokens,[ref]$workerErrors) | Out-Null
    if ($workerErrors.Count -gt 0) { throw ('WORKER_PARSE_FAILED: ' + $id) }

    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $workerPath + '"'
    $action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $arguments
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($repeat,$logon) -Settings $settings -Principal $principal -Force | Out-Null
    $taskNames += $taskName
}

Disable-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue | Out-Null
foreach ($taskName in $taskNames) { Start-ScheduledTask -TaskName $taskName }

Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER V1.1.3 - PARALELO PREAQUECIDO ATIVO' -ForegroundColor Green
Write-Host ('Workers: ' + ($taskNames -join ', ')) -ForegroundColor Cyan
Write-Host 'Clones locais separados foram preparados antes do paralelismo para evitar travamento de credenciais.' -ForegroundColor Green
Write-Host 'Junior Resolve e Orcamento no Ponto foram disparados em paralelo.' -ForegroundColor Green