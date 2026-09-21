param(
  [string]$Root = "E:\BlackGold_Remote_Bridge",
  [string]$Repo = "https://github.com/ProjetosCosaNostra/BlackVault_Sentinel.git",
  [string]$Branch = "blackgold-remote-bridge-v1"
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Version='1.2.0'
$ReleaseBranch='blackgold-remote-bridge-v1_2'
$ReleaseBase="https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/$ReleaseBranch/blackgold-remote-bridge"

Write-Host "BlackGold Remote Bridge V$Version" -ForegroundColor Yellow
if(-not(Get-Command git.exe -ErrorAction SilentlyContinue)){throw "Git nao encontrado no PATH."}
if(-not(Test-Path 'E:\')){throw "Unidade E: nao encontrada."}

New-Item -ItemType Directory -Force -Path $Root,(Join-Path $Root 'logs')|Out-Null
foreach($name in @('agent.ps1','watchdog.ps1')){
  Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseBase/$name" -OutFile (Join-Path $Root $name)
}

$control=Join-Path $Root 'control'
if(-not(Test-Path(Join-Path $control '.git'))){
  if(Test-Path $control){Remove-Item -Recurse -Force $control}
  & git clone --depth 1 --single-branch --branch $Branch $Repo $control
  if($LASTEXITCODE-ne0){throw "Falha no clone privado. Conclua o login do Git Credential Manager e execute novamente."}
}else{
  Push-Location $control
  try{
    & git fetch origin
    & git checkout $Branch
    & git pull --rebase origin $Branch
    if($LASTEXITCODE-ne0){throw "Falha ao atualizar o repositorio de controle."}
  }finally{Pop-Location}
}

Push-Location $control
try{
  & git config user.name "BlackGold Remote Bridge"
  & git config user.email "blackgold-remote@local.invalid"
  & git ls-remote origin HEAD *> $null
  if($LASTEXITCODE-ne0){throw "Autenticacao GitHub indisponivel."}
}finally{Pop-Location}

$cfg=[ordered]@{
  version=$Version
  branch=$Branch
  repo_root=$control
  poll_seconds=8
  max_output_chars=500000
  log_file=(Join-Path $Root 'logs\bridge.log')
  disabled_flag=(Join-Path $Root 'DISABLED.flag')
  allowed_roots=@('E:\',"$env:USERPROFILE\Desktop","$env:USERPROFILE\Documents","$env:TEMP\BlackGold_Remote_Bridge")
  denied_paths=@(
    '(?i)\\AppData\\Local\\Google\\Chrome\\User Data',
    '(?i)\\AppData\\Local\\Microsoft\\Edge\\User Data',
    '(?i)\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles',
    '(?i)\\\.ssh(\\|$)',
    '(?i)\\\.aws(\\|$)',
    '(?i)\\Microsoft\\Credentials(\\|$)',
    '(?i)\\Windows\\System32\\config\\(SAM|SECURITY|SYSTEM)$'
  )
  allowed_exec=@(
    'git.exe','git','adb.exe','adb','gradlew.bat','gradlew',
    'flutter.bat','flutter','dart.exe','dart','java.exe','java',
    'python.exe','python','py.exe','py','node.exe','node',
    'npm.cmd','npm','npx.cmd','npx','emulator.exe','emulator',
    'studio64.exe','code.cmd','code'
  )
}
$configPath=Join-Path $Root 'config.json'
$cfg|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding UTF8

$enable=@'
$root='E:\BlackGold_Remote_Bridge'
$f=Join-Path $root 'DISABLED.flag'
if(Test-Path $f){Remove-Item -Force $f}
Start-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'BlackGold_Remote_Bridge_Watchdog' -ErrorAction SilentlyContinue
'@
$disable=@'
$root='E:\BlackGold_Remote_Bridge'
New-Item -ItemType Directory -Force -Path $root|Out-Null
Set-Content -LiteralPath (Join-Path $root 'DISABLED.flag') -Value ((Get-Date).ToString('o'))
Stop-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName 'BlackGold_Remote_Bridge_Watchdog' -ErrorAction SilentlyContinue
'@
$status=@'
$names=@('BlackGold_Remote_Bridge','BlackGold_Remote_Bridge_Watchdog')
foreach($name in $names){
  $t=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  $i=if($t){$t|Get-ScheduledTaskInfo}else{$null}
  [pscustomobject]@{
    Task=$name
    Installed=[bool]$t
    State=if($t){$t.State}else{'NOT_INSTALLED'}
    LastRunTime=if($i){$i.LastRunTime}else{$null}
    LastTaskResult=if($i){$i.LastTaskResult}else{$null}
  }
}
[pscustomobject]@{
  Disabled=Test-Path 'E:\BlackGold_Remote_Bridge\DISABLED.flag'
  Config='E:\BlackGold_Remote_Bridge\config.json'
  Log='E:\BlackGold_Remote_Bridge\logs\bridge.log'
}|Format-List
'@
$repair="$ErrorActionPreference='Stop'; irm '$ReleaseBase/install.ps1' | iex"
Set-Content -LiteralPath (Join-Path $Root 'enable.ps1') -Value $enable -Encoding UTF8
Set-Content -LiteralPath (Join-Path $Root 'disable.ps1') -Value $disable -Encoding UTF8
Set-Content -LiteralPath (Join-Path $Root 'status.ps1') -Value $status -Encoding UTF8
Set-Content -LiteralPath (Join-Path $Root 'repair.ps1') -Value $repair -Encoding UTF8

$agentPath=Join-Path $Root 'agent.ps1'
$watchdogPath=Join-Path $Root 'watchdog.ps1'
$agentArgs="-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $agentPath -ConfigPath $configPath"
$agentAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $agentArgs
$logonTrigger=New-ScheduledTaskTrigger -AtLogOn
$agentSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Unregister-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -Action $agentAction -Trigger $logonTrigger -Settings $agentSettings -Principal $principal -Description 'BlackGold private outbound remote bridge V1.2'|Out-Null

$watchdogArgs="-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $watchdogPath -Root $Root"
$watchdogAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $watchdogArgs
$watchdogLogon=New-ScheduledTaskTrigger -AtLogOn
$watchdogRepeat=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$watchdogSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName 'BlackGold_Remote_Bridge_Watchdog' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BlackGold_Remote_Bridge_Watchdog' -Action $watchdogAction -Trigger @($watchdogLogon,$watchdogRepeat) -Settings $watchdogSettings -Principal $principal -Description 'Watchdog BlackGold Remote Bridge V1.2'|Out-Null

$desk=[Environment]::GetFolderPath('Desktop')
$ws=New-Object -ComObject WScript.Shell
foreach($x in @(@('LIGAR','enable.ps1'),@('DESLIGAR','disable.ps1'),@('STATUS','status.ps1'),@('REPARAR','repair.ps1'))){
  $s=$ws.CreateShortcut((Join-Path $desk ("BlackGold Remote - "+$x[0]+".lnk")))
  $s.TargetPath='powershell.exe'
  $s.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $Root\$($x[1])"
  $s.WorkingDirectory=$Root
  $s.Save()
}

$f=Join-Path $Root 'DISABLED.flag'
if(Test-Path $f){Remove-Item -Force $f}
Start-ScheduledTask -TaskName 'BlackGold_Remote_Bridge'
Start-ScheduledTask -TaskName 'BlackGold_Remote_Bridge_Watchdog'
Start-Sleep -Seconds 3

$task=Get-ScheduledTask -TaskName 'BlackGold_Remote_Bridge'
$info=$task|Get-ScheduledTaskInfo
[ordered]@{
  version=$Version
  installed_at=(Get-Date).ToString('o')
  computer=$env:COMPUTERNAME
  user=$env:USERNAME
  task_state=[string]$task.State
  last_task_result=$info.LastTaskResult
  control_branch=$Branch
  root=$Root
}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Root 'install-health.json') -Encoding UTF8

Write-Host ""
Write-Host "BLACKGOLD REMOTE BRIDGE V1.2 INSTALADO" -ForegroundColor Green
Write-Host "Pasta: $Root"
Write-Host "Controle: GitHub privado / $Branch"
Write-Host "Portas de entrada: 0"
Write-Host "Watchdog: ATIVO"
Write-Host "PowerShell arbitrario: REMOVIDO"
Write-Host "Atalhos LIGAR, DESLIGAR, STATUS e REPARAR criados."
