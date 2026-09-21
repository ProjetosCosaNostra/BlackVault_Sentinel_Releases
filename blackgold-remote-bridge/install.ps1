param(
  [string]$Root = "E:\BlackGold_Remote_Bridge",
  [string]$Repo = "https://github.com/ProjetosCosaNostra/BlackVault_Sentinel.git",
  [string]$Branch = "blackgold-remote-bridge-v1"
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Write-Host "BlackGold Remote Bridge V1.1" -ForegroundColor Yellow

if(-not(Get-Command git.exe -ErrorAction SilentlyContinue)){throw "Git nao encontrado no PATH."}
New-Item -ItemType Directory -Force -Path $Root,(Join-Path $Root 'logs')|Out-Null

$agentUrl="https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/blackgold-remote-bridge-v1_1/blackgold-remote-bridge/agent.ps1"
Invoke-WebRequest -UseBasicParsing -Uri $agentUrl -OutFile (Join-Path $Root 'agent.ps1')

$control=Join-Path $Root 'control'
if(-not(Test-Path(Join-Path $control '.git'))){
  if(Test-Path $control){Remove-Item -Recurse -Force $control}
  & git clone --depth 1 --single-branch --branch $Branch $Repo $control
  if($LASTEXITCODE-ne0){throw "Nao consegui acessar o repositorio privado. Conclua o login do Git Credential Manager e rode o instalador de novo."}
}else{
  Push-Location $control
  try{& git fetch origin;& git checkout $Branch;& git pull --rebase origin $Branch}
  finally{Pop-Location}
}

Push-Location $control
try{
  & git config user.name "BlackGold Remote Bridge"
  & git config user.email "blackgold-remote@local.invalid"
  & git ls-remote origin HEAD *> $null
  if($LASTEXITCODE-ne0){throw "Autenticacao GitHub indisponivel neste Windows."}
}finally{Pop-Location}

$cfg=[ordered]@{
  version='1.1.0'
  branch=$Branch
  repo_root=$control
  poll_seconds=8
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
  denied_commands=@(
    '(?i)mimikatz|sekurlsa|comsvcs\.dll.*MiniDump|lsass',
    '(?i)reg\s+save\s+HKLM\\(SAM|SECURITY|SYSTEM)',
    '(?i)ntdsutil|vssadmin\s+delete|wbadmin\s+delete',
    '(?i)diskpart|format\s+[A-Z]:|cipher\s+/w',
    '(?i)Stop-Computer|Restart-Computer|shutdown\.exe\s+/(s|r)',
    '(?i)bcdedit|bootrec'
  )
}
$configPath=Join-Path $Root 'config.json'
$cfg|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $configPath -Encoding UTF8

$enable=@'
$root='E:\BlackGold_Remote_Bridge'
$f=Join-Path $root 'DISABLED.flag'
if(Test-Path $f){Remove-Item -Force $f}
Start-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -ErrorAction SilentlyContinue
'@
$disable=@'
$root='E:\BlackGold_Remote_Bridge'
New-Item -ItemType Directory -Force -Path $root|Out-Null
Set-Content -LiteralPath (Join-Path $root 'DISABLED.flag') -Value ((Get-Date).ToString('o'))
Stop-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -ErrorAction SilentlyContinue
'@
$status=@'
$t=Get-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -ErrorAction SilentlyContinue
$i=if($t){$t|Get-ScheduledTaskInfo}else{$null}
[pscustomobject]@{
 Installed=[bool]$t
 State=if($t){$t.State}else{'NOT_INSTALLED'}
 LastRunTime=if($i){$i.LastRunTime}else{$null}
 LastTaskResult=if($i){$i.LastTaskResult}else{$null}
 Disabled=Test-Path 'E:\BlackGold_Remote_Bridge\DISABLED.flag'
 Log='E:\BlackGold_Remote_Bridge\logs\bridge.log'
}|Format-List
'@
Set-Content -LiteralPath (Join-Path $Root 'enable.ps1') -Value $enable -Encoding UTF8
Set-Content -LiteralPath (Join-Path $Root 'disable.ps1') -Value $disable -Encoding UTF8
Set-Content -LiteralPath (Join-Path $Root 'status.ps1') -Value $status -Encoding UTF8

$agentPath=Join-Path $Root 'agent.ps1'
$taskArgs="-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $agentPath -ConfigPath $configPath"
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs
$trigger=New-ScheduledTaskTrigger -AtLogOn
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Unregister-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'BlackGold_Remote_Bridge' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'BlackGold private outbound remote bridge'|Out-Null

$desk=[Environment]::GetFolderPath('Desktop')
$ws=New-Object -ComObject WScript.Shell
foreach($x in @(@('LIGAR','enable.ps1'),@('DESLIGAR','disable.ps1'))){
  $s=$ws.CreateShortcut((Join-Path $desk ("BlackGold Remote - "+$x[0]+".lnk")))
  $s.TargetPath='powershell.exe'
  $s.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $Root\$($x[1])"
  $s.WorkingDirectory=$Root
  $s.Save()
}

$f=Join-Path $Root 'DISABLED.flag'
if(Test-Path $f){Remove-Item -Force $f}
Start-ScheduledTask -TaskName 'BlackGold_Remote_Bridge'
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "BLACKGOLD REMOTE BRIDGE V1.1 INSTALADO" -ForegroundColor Green
Write-Host "Pasta: $Root"
Write-Host "Controle: GitHub privado / $Branch"
Write-Host "Portas de entrada: 0"
Write-Host "Atalhos LIGAR e DESLIGAR criados na Area de Trabalho."
