$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_1_1.new.ps1'
$ConfigPath = Join-Path $Base 'projects.json'
$WorkersDir = Join-Path $Base 'workers'
$LegacyTask = 'BlackGold_Project_Runner_V1'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/c1aeeb5aa463027a9e11b0c461bbf1c4814f6eb3/blackgold-project-runner/runner_v1_1_1.ps1'

New-Item -ItemType Directory -Force -Path $Base,$WorkersDir | Out-Null
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "CONFIG_NOT_FOUND: $ConfigPath" }

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'RUNNER_DOWNLOAD_FAILED' }
$runnerText = Get-Content -LiteralPath $TempPath -Raw
if ($runnerText -notmatch "RunnerVersion\s*=\s*'1\.1\.1'") { throw 'RUNNER_VERSION_MISMATCH' }
if ($runnerText -match 'Invoke-Expression|iex\s') { throw 'UNSAFE_RUNNER_REJECTED' }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    throw ('RUNNER_PARSE_FAILED: ' + $messages)
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$projects = @($config.projects)
if ($projects.Count -lt 1) { throw 'NO_REGISTERED_PROJECTS' }

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $RunnerPath) {
    $backup = Join-Path $Base ('runner.before-v1_1_1.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ps1')
    Copy-Item -LiteralPath $RunnerPath -Destination $backup -Force
}
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

$taskNames = @()
$workerFiles = @()

foreach ($project in $projects) {
    $id = [string]$project.id
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $safe = $id -replace '[^A-Za-z0-9_-]','_'
    $taskName = 'BlackGold_Project_Runner_' + $safe
    $workerPath = Join-Path $WorkersDir ($safe + '.ps1')

    $workerLines = @(
        '$ErrorActionPreference = ''Stop'''
        ('$env:BLACKGOLD_PROJECT_FILTER = ''' + $id + '''')
        ('& ''' + $ps + ''' -NoProfile -ExecutionPolicy Bypass -File ''' + $RunnerPath + '''')
        'exit $LASTEXITCODE'
    )
    [IO.File]::WriteAllText($workerPath,($workerLines -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))

    $workerTokens = $null
    $workerErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($workerPath,[ref]$workerTokens,[ref]$workerErrors) | Out-Null
    if ($workerErrors.Count -gt 0) { throw ('WORKER_PARSE_FAILED: ' + $id) }

    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $workerPath + '"'
    $action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($repeat,$logon) -Settings $settings -Principal $principal -Force | Out-Null

    $taskNames += $taskName
    $workerFiles += $workerPath
}

Disable-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue | Out-Null

$runAllPath = Join-Path $Base 'RUN_ALL_PROJECTS_NOW.ps1'
$runAllLines = @(
    '$ErrorActionPreference = ''Continue'''
    ('$ps = ''' + $ps + '''')
)
foreach ($workerPath in $workerFiles) {
    $runAllLines += ('Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ''-NoProfile -ExecutionPolicy Bypass -File "' + $workerPath + '"''')
}
$runAllLines += "Write-Host 'BlackGold: workers disparados em paralelo.' -ForegroundColor Green"
[IO.File]::WriteAllText($runAllPath,($runAllLines -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))

foreach ($taskName in $taskNames) { Start-ScheduledTask -TaskName $taskName }

Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER V1.1.1 - PARALELO ATIVO' -ForegroundColor Green
Write-Host ('Workers: ' + ($taskNames -join ', ')) -ForegroundColor Cyan
Write-Host ('Executar todos agora: ' + $runAllPath) -ForegroundColor Cyan
Write-Host 'Junior Resolve e Orcamento no Ponto agora executam sem disputar o mesmo lock.' -ForegroundColor Green