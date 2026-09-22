$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_1_0.new.ps1'
$ConfigPath = Join-Path $Base 'projects.json'
$WorkersDir = Join-Path $Base 'workers'
$LegacyTask = 'BlackGold_Project_Runner_V1'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/8ecd6d39cf602435dddd5836a46cf3b8a0b957a2/blackgold-project-runner/runner.ps1'

New-Item -ItemType Directory -Force -Path $Base,$WorkersDir | Out-Null
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config nao encontrada: $ConfigPath" }

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.1\.0'") { throw 'Runner baixado nao e V1.1.0.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    throw ("Runner V1.1.0 recusado pelo parser: " + $messages)
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$projects = @($config.projects)
if (-not $projects.Count) { throw 'Nenhum projeto registrado no BlackGold Project Runner.' }

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $RunnerPath) {
    $backup = Join-Path $Base ('runner.before-v1_1_0.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ps1')
    Copy-Item -LiteralPath $RunnerPath -Destination $backup -Force
}
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

$createdTasks = @()
$workerFiles = @()

foreach ($project in $projects) {
    $id = [string]$project.id
    if ($id -notmatch '^[a-z0-9._-]+$') { throw "INVALID_PROJECT_ID_IN_CONFIG: $id" }

    $safe = ($id -replace '[^A-Za-z0-9_-]','_')
    $taskName = 'BlackGold_Project_Runner_' + $safe
    $workerPath = Join-Path $WorkersDir ($safe + '.ps1')

    $worker = @(
        '$ErrorActionPreference = ''Stop''',
        ('$env:BLACKGOLD_PROJECT_FILTER = ''' + $id + ''''),
        ('& ''' + $ps + ''' -NoProfile -ExecutionPolicy Bypass -File ''' + $RunnerPath + ''''),
        'exit $LASTEXITCODE'
    ) -join [Environment]::NewLine

    [IO.File]::WriteAllText($workerPath,$worker,[Text.UTF8Encoding]::new($false))

    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $workerPath + '"'
    $action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(25) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($repeat,$logon) -Settings $settings -Principal $principal -Force | Out-Null
    $createdTasks += $taskName
    $workerFiles += $workerPath
}

Disable-ScheduledTask -TaskName $LegacyTask -ErrorAction SilentlyContinue | Out-Null

$runAllPath = Join-Path $Base 'RUN_ALL_PROJECTS_NOW.ps1'
$runAll = @(
    '$ErrorActionPreference = ''Continue''',
    '$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"'
)
foreach ($workerPath in $workerFiles) {
    $runAll += ('Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList ''-NoProfile -ExecutionPolicy Bypass -File "' + $workerPath + '"''')
}
$runAll += "Write-Host 'BlackGold: todos os workers foram disparados em paralelo.' -ForegroundColor Green"
[IO.File]::WriteAllText($runAllPath,($runAll -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))

foreach ($taskName in $createdTasks) {
    Start-ScheduledTask -TaskName $taskName
}

Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER V1.1.0 - MODO MULTIPROJETO PARALELO ATIVO' -ForegroundColor Green
Write-Host ('Workers: ' + ($createdTasks -join ', ')) -ForegroundColor Cyan
Write-Host ('Executar todos agora: ' + $runAllPath) -ForegroundColor Cyan
Write-Host 'Cada projeto usa lock, log e clone do control plane separados.' -ForegroundColor Green
Write-Host 'Um projeto nao bloqueia mais a fila do outro.' -ForegroundColor Green
