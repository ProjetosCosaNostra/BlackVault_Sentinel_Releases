$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RunnerVersion = '1.0.0'
$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$ControlRepo = Join-Path $Base 'control'
$ConfigPath = Join-Path $Base 'projects.json'
$LogsDir = Join-Path $Base 'logs'
$LockPath = Join-Path $Base 'runner.lock'
$Branch = 'blackgold-project-runner-v1'
$ManagedRoot = 'project_runner'
$InboxRel = 'project_runner\jobs\inbox'
$OutboxRel = 'project_runner\jobs\outbox'
$HeartbeatRel = 'project_runner\heartbeats'

New-Item -ItemType Directory -Force -Path $Base,$LogsDir | Out-Null

try {
    $LockStream = [IO.File]::Open($LockPath,'OpenOrCreate','ReadWrite','None')
} catch {
    exit 0
}

function Write-JsonFile([object]$Value,[string]$Path) {
    $json = $Value | ConvertTo-Json -Depth 20
    $parent = Split-Path -Parent $Path
    if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::WriteAllText($Path,$json,[Text.UTF8Encoding]::new($false))
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "JSON_NOT_FOUND: $Path" }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Normalize-Path([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-UnderRoot([string]$Path,[string]$Root) {
    $p = Normalize-Path $Path
    $r = Normalize-Path $Root
    return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($r + '\',[StringComparison]::OrdinalIgnoreCase)
}

function Get-Config {
    return Read-JsonFile $ConfigPath
}

function Save-Config([object]$Config) {
    Write-JsonFile $Config $ConfigPath
}

function Get-Project([string]$ProjectId) {
    if ($ProjectId -notmatch '^[a-z0-9._-]+$') { throw "INVALID_PROJECT_ID: $ProjectId" }
    $cfg = Get-Config
    $project = @($cfg.projects | Where-Object { $_.id -eq $ProjectId }) | Select-Object -First 1
    if (-not $project) { throw "PROJECT_NOT_REGISTERED: $ProjectId" }
    if (-not (Test-Path -LiteralPath $project.root)) { throw "PROJECT_ROOT_NOT_FOUND: $($project.root)" }
    return $project
}

function Assert-AllowedLocalRoot([string]$Root) {
    $cfg = Get-Config
    $ok = $false
    foreach ($allowed in @($cfg.allowed_roots)) {
        if (Test-UnderRoot $Root $allowed) { $ok = $true; break }
    }
    if (-not $ok) { throw "ROOT_NOT_ALLOWED: $Root" }
}

function Sync-ControlRepo {
    $git = (Get-Command git.exe -ErrorAction Stop).Source
    if (-not (Test-Path -LiteralPath (Join-Path $ControlRepo '.git'))) {
        throw "CONTROL_REPO_NOT_CLONED: $ControlRepo"
    }
    & $git -C $ControlRepo config core.longpaths true | Out-Null
    & $git -C $ControlRepo fetch origin $Branch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_FETCH_FAILED' }
    & $git -C $ControlRepo checkout $Branch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_CHECKOUT_FAILED' }
    & $git -C $ControlRepo reset --hard ("origin/" + $Branch) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_RESET_FAILED' }
}

function Publish-ControlChanges {
    $git = (Get-Command git.exe -ErrorAction Stop).Source
    & $git -C $ControlRepo add -- $OutboxRel $HeartbeatRel | Out-Null
    $changes = & $git -C $ControlRepo status --porcelain -- $OutboxRel $HeartbeatRel
    if (-not $changes) { return }
    & $git -C $ControlRepo config user.name 'BlackGold Project Runner'
    & $git -C $ControlRepo config user.email 'blackgold-project-runner@local.invalid'
    & $git -C $ControlRepo commit -m ("runner: publish " + (Get-Date -Format 'yyyyMMdd-HHmmss')) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_COMMIT_FAILED' }
    & $git -C $ControlRepo pull --rebase origin $Branch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_REBASE_FAILED' }
    & $git -C $ControlRepo push origin $Branch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_PUSH_FAILED' }
}

function Get-AndroidRoot([object]$Project) {
    if (-not $Project.android_project) { throw "ANDROID_PROJECT_NOT_CONFIGURED: $($Project.id)" }
    $root = Join-Path $Project.root $Project.android_project
    if (-not (Test-Path -LiteralPath $root)) { throw "ANDROID_PROJECT_NOT_FOUND: $root" }
    return $root
}

function Invoke-GradleTask([object]$Project,[string]$Task,[string]$LogPath) {
    $androidRoot = Get-AndroidRoot $Project
    $wrapper = Join-Path $androidRoot 'gradlew.bat'
    $cmd = $null
    Push-Location $androidRoot
    try {
        if (Test-Path -LiteralPath $wrapper) {
            & $wrapper --no-daemon $Task *> $LogPath
        } else {
            $cmd = Get-Command gradle.bat -ErrorAction SilentlyContinue
            if (-not $cmd) { $cmd = Get-Command gradle -ErrorAction SilentlyContinue }
            if (-not $cmd) { throw 'GRADLE_NOT_FOUND' }
            & $cmd.Source --no-daemon $Task *> $LogPath
        }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) { throw "GRADLE_FAILED_$code : $Task" }
}

function Find-LatestDebugApk([object]$Project) {
    $androidRoot = Get-AndroidRoot $Project
    $dir = Join-Path $androidRoot 'app\build\outputs\apk\debug'
    $apk = Get-ChildItem -LiteralPath $dir -Filter '*.apk' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $apk) { throw "DEBUG_APK_NOT_FOUND: $dir" }
    return $apk.FullName
}

function Get-Adb {
    $candidates = @()
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe') }
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe') }
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'ADB_NOT_FOUND'
}

function Get-EmulatorExe {
    $candidates = @()
    if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT 'emulator\emulator.exe') }
    if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME 'emulator\emulator.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe') }
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    $cmd = Get-Command emulator.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'EMULATOR_EXE_NOT_FOUND'
}

function Get-RunningTargetSerial([object]$Project) {
    if (-not $Project.avd) { throw "AVD_NOT_CONFIGURED: $($Project.id)" }
    $adb = Get-Adb
    $rows = & $adb devices
    foreach ($row in @($rows)) {
        if ($row -match '^(\S+)\s+device$') {
            $serial = $Matches[1]
            $nameLines = @(& $adb -s $serial emu avd name 2>$null)
            $name = @($nameLines | Where-Object { $_ -and $_ -ne 'OK' }) | Select-Object -First 1
            if ($name -and $name.Trim() -eq [string]$Project.avd) { return $serial }
        }
    }
    return $null
}

function Start-TargetEmulator([object]$Project,[int]$TimeoutSeconds = 180) {
    $serial = Get-RunningTargetSerial $Project
    if ($serial) { return $serial }

    $emulator = Get-EmulatorExe
    $avds = @(& $emulator -list-avds)
    if (-not ($avds -contains [string]$Project.avd)) {
        throw "AVD_NOT_FOUND: $($Project.avd)"
    }

    Start-Process -FilePath $emulator -ArgumentList @('-avd',[string]$Project.avd,'-no-snapshot-save') | Out-Null
    $adb = Get-Adb
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $serial = Get-RunningTargetSerial $Project
        if ($serial) {
            $boot = (& $adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
            if ($boot -eq '1') { return $serial }
        }
    } while ((Get-Date) -lt $deadline)

    throw "AVD_BOOT_TIMEOUT: $($Project.avd)"
}

function Capture-Screenshot([object]$Project,[string]$JobId) {
    $serial = Start-TargetEmulator $Project
    $adb = Get-Adb
    $localDir = Join-Path $Base 'captures'
    New-Item -ItemType Directory -Force -Path $localDir | Out-Null
    $png = Join-Path $localDir ($JobId + '.png')
    $remote = '/sdcard/blackgold_runner.png'
    & $adb -s $serial shell screencap -p $remote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'SCREENSHOT_CAPTURE_FAILED' }
    & $adb -s $serial pull $remote $png | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'SCREENSHOT_PULL_FAILED' }
    & $adb -s $serial shell rm $remote | Out-Null

    $size = (Get-Item -LiteralPath $png).Length
    if ($size -gt 2097152) { throw "SCREENSHOT_TOO_LARGE: $size" }

    $outbox = Join-Path $ControlRepo $OutboxRel
    New-Item -ItemType Directory -Force -Path $outbox | Out-Null
    $b64Path = Join-Path $outbox ($JobId + '.screenshot.b64')
    [IO.File]::WriteAllText(
        $b64Path,
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($png)),
        [Text.UTF8Encoding]::new($false)
    )

    $xmlRemote = '/sdcard/blackgold_runner.xml'
    $xmlLocal = Join-Path $outbox ($JobId + '.uiautomator.xml')
    & $adb -s $serial shell uiautomator dump $xmlRemote 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & $adb -s $serial pull $xmlRemote $xmlLocal 2>$null | Out-Null
        & $adb -s $serial shell rm $xmlRemote 2>$null | Out-Null
    }

    return [ordered]@{
        serial = $serial
        local_png = $png
        screenshot_b64 = ($OutboxRel + '\' + $JobId + '.screenshot.b64')
        uiautomator_xml = $(if (Test-Path -LiteralPath $xmlLocal) { $OutboxRel + '\' + $JobId + '.uiautomator.xml' } else { $null })
        sha256 = (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes = $size
    }
}

function Apply-Patch([object]$Project,[object]$Job,[string]$JobLog) {
    $payloadRel = if ($Job.args.payload_dir) { [string]$Job.args.payload_dir } else { "project_runner\payloads\$($Job.id)" }
    $payloadRoot = Normalize-Path (Join-Path $ControlRepo $payloadRel)
    $controlFull = Normalize-Path $ControlRepo
    if (-not (Test-UnderRoot $payloadRoot $controlFull)) { throw 'PAYLOAD_OUTSIDE_CONTROL_REPO' }
    if (-not (Test-Path -LiteralPath $payloadRoot)) { throw "PAYLOAD_NOT_FOUND: $payloadRel" }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = Join-Path $Project.root ("99_Backups\BPR\$timestamp")
    $backupFiles = Join-Path $backup 'files'
    New-Item -ItemType Directory -Force -Path $backupFiles | Out-Null

    $changed = @()
    $records = @()
    $index = 0
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File)) {
            $relative = $file.FullName.Substring($payloadRoot.Length).TrimStart('\')
            $allowed = $false
            foreach ($patchRoot in @($Project.patch_roots)) {
                if ($relative.StartsWith(([string]$patchRoot).TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase) -or
                    $relative.Equals(([string]$patchRoot).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) {
                    $allowed = $true
                    break
                }
            }
            if (-not $allowed) { throw "PATCH_PATH_NOT_ALLOWED: $relative" }

            $leaf = [IO.Path]::GetFileName($relative)
            foreach ($pattern in @($Project.protected_file_patterns)) {
                if ($leaf -like [string]$pattern) { throw "PROTECTED_FILE: $relative" }
            }

            $destination = Join-Path $Project.root $relative
            if (-not (Test-UnderRoot $destination $Project.root)) { throw "PATCH_ESCAPE_BLOCKED: $relative" }

            $index++
            $existed = Test-Path -LiteralPath $destination
            $backupFile = ''
            if ($existed) {
                $backupFile = Join-Path $backupFiles (('{0:D3}.bak' -f $index))
                Copy-Item -LiteralPath $destination -Destination $backupFile -Force
            }
            $targetDir = Split-Path -Parent $destination
            if ($targetDir) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            $records += [pscustomobject]@{ destination=$destination; backup=$backupFile; existed=$existed }
            $changed += $relative
        }

        $verifyBuild = $true
        if ($null -ne $Job.args.verify_build) { $verifyBuild = [bool]$Job.args.verify_build }
        if ($verifyBuild -and $Project.android_project) {
            Invoke-GradleTask $Project ':app:assembleDebug' $JobLog
        }
    } catch {
        for ($i=$records.Count-1; $i -ge 0; $i--) {
            $rec=$records[$i]
            if ($rec.existed) { Copy-Item -LiteralPath $rec.backup -Destination $rec.destination -Force }
            else { Remove-Item -LiteralPath $rec.destination -Force -ErrorAction SilentlyContinue }
        }
        throw
    }

    return [ordered]@{ backup=$backup; changed_files=@($changed); build_verified=$verifyBuild }
}

function Register-Project([object]$Job) {
    $id = [string]$Job.args.id
    if ($id -notmatch '^[a-z0-9._-]+$') { throw "INVALID_PROJECT_ID: $id" }
    $root = Normalize-Path ([string]$Job.args.root)
    Assert-AllowedLocalRoot $root
    if (-not (Test-Path -LiteralPath $root)) { throw "PROJECT_ROOT_NOT_FOUND: $root" }

    $cfg = Get-Config
    $projects = @($cfg.projects | Where-Object { $_.id -ne $id })
    $entry = [pscustomobject]@{
        id = $id
        root = $root
        android_project = [string]$Job.args.android_project
        application_id = [string]$Job.args.application_id
        avd = [string]$Job.args.avd
        patch_roots = @($Job.args.patch_roots)
        protected_file_patterns = @($Job.args.protected_file_patterns)
    }
    $cfg.projects = @($projects + $entry)
    Save-Config $cfg
    return $entry
}

function Discover-Projects {
    $cfg = Get-Config
    $found = @()
    foreach ($root in @($cfg.allowed_roots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $markers = @()
            if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) { $markers += 'git' }
            if (Get-ChildItem -LiteralPath $dir.FullName -Filter 'settings.gradle*' -File -ErrorAction SilentlyContinue) { $markers += 'android' }
            if (Test-Path -LiteralPath (Join-Path $dir.FullName 'pubspec.yaml')) { $markers += 'flutter' }
            if ($markers.Count -gt 0) {
                $found += [pscustomobject]@{ name=$dir.Name; root=$dir.FullName; markers=$markers }
            }
        }
    }
    return @($found)
}

function Invoke-Job([object]$Job,[string]$JobLog) {
    $action = [string]$Job.action
    switch ($action) {
        'health' {
            return [ordered]@{
                runner_version=$RunnerVersion
                computer=$env:COMPUTERNAME
                user=$env:USERNAME
                powershell=$PSVersionTable.PSVersion.ToString()
                time=(Get-Date -Format o)
            }
        }
        'discover_projects' { return [ordered]@{ projects=(Discover-Projects) } }
        'register_project' { return [ordered]@{ project=(Register-Project $Job) } }
        'project_status' {
            $project=Get-Project ([string]$Job.project)
            return [ordered]@{
                id=$project.id
                root=$project.root
                android_project=$project.android_project
                application_id=$project.application_id
                avd=$project.avd
                root_exists=(Test-Path -LiteralPath $project.root)
            }
        }
        'build_debug' {
            $project=Get-Project ([string]$Job.project)
            Invoke-GradleTask $project ':app:assembleDebug' $JobLog
            return [ordered]@{ apk=(Find-LatestDebugApk $project); log=$JobLog }
        }
        'lint' {
            $project=Get-Project ([string]$Job.project)
            Invoke-GradleTask $project ':app:lintDebug' $JobLog
            return [ordered]@{ log=$JobLog }
        }
        'start_emulator' {
            $project=Get-Project ([string]$Job.project)
            return [ordered]@{ serial=(Start-TargetEmulator $project); avd=$project.avd }
        }
        'install_debug' {
            $project=Get-Project ([string]$Job.project)
            $serial=Start-TargetEmulator $project
            $apk=Find-LatestDebugApk $project
            $adb=Get-Adb
            & $adb -s $serial install -r $apk *> $JobLog
            if ($LASTEXITCODE -ne 0) { throw "ADB_INSTALL_FAILED_$LASTEXITCODE" }
            return [ordered]@{ serial=$serial; apk=$apk; log=$JobLog }
        }
        'launch_app' {
            $project=Get-Project ([string]$Job.project)
            if (-not $project.application_id) { throw 'APPLICATION_ID_NOT_CONFIGURED' }
            $serial=Start-TargetEmulator $project
            $adb=Get-Adb
            & $adb -s $serial shell monkey -p ([string]$project.application_id) -c android.intent.category.LAUNCHER 1 *> $JobLog
            if ($LASTEXITCODE -ne 0) { throw "APP_LAUNCH_FAILED_$LASTEXITCODE" }
            return [ordered]@{ serial=$serial; application_id=$project.application_id; log=$JobLog }
        }
        'screenshot' {
            $project=Get-Project ([string]$Job.project)
            return (Capture-Screenshot $project ([string]$Job.id))
        }
        'build_install_launch_screenshot' {
            $project=Get-Project ([string]$Job.project)
            Invoke-GradleTask $project ':app:assembleDebug' $JobLog
            $serial=Start-TargetEmulator $project
            $apk=Find-LatestDebugApk $project
            $adb=Get-Adb
            & $adb -s $serial install -r $apk *> $JobLog
            if ($LASTEXITCODE -ne 0) { throw "ADB_INSTALL_FAILED_$LASTEXITCODE" }
            & $adb -s $serial shell monkey -p ([string]$project.application_id) -c android.intent.category.LAUNCHER 1 >> $JobLog
            if ($LASTEXITCODE -ne 0) { throw "APP_LAUNCH_FAILED_$LASTEXITCODE" }
            Start-Sleep -Seconds 3
            $shot=Capture-Screenshot $project ([string]$Job.id)
            return [ordered]@{ apk=$apk; serial=$serial; screenshot=$shot; log=$JobLog }
        }
        'apply_patch' {
            $project=Get-Project ([string]$Job.project)
            return (Apply-Patch $project $Job $JobLog)
        }
        default { throw "ACTION_NOT_ALLOWED: $action" }
    }
}

function Write-Heartbeat {
    $hbDir = Join-Path $ControlRepo $HeartbeatRel
    New-Item -ItemType Directory -Force -Path $hbDir | Out-Null
    $cfg=Get-Config
    $value=[ordered]@{
        schema='blackgold.project-runner.heartbeat.v1'
        runner_version=$RunnerVersion
        computer=$env:COMPUTERNAME
        user=$env:USERNAME
        time=(Get-Date -Format o)
        projects=@($cfg.projects | ForEach-Object { $_.id })
    }
    Write-JsonFile $value (Join-Path $hbDir (($env:COMPUTERNAME) + '.json'))
}

try {
    Sync-ControlRepo
    Write-Heartbeat

    $inbox = Join-Path $ControlRepo $InboxRel
    $outbox = Join-Path $ControlRepo $OutboxRel
    New-Item -ItemType Directory -Force -Path $inbox,$outbox | Out-Null

    $jobFile = Get-ChildItem -LiteralPath $inbox -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -First 1

    if ($jobFile) {
        $job=Read-JsonFile $jobFile.FullName
        $jobId=[string]$job.id
        if ($jobId -notmatch '^[A-Za-z0-9._-]+$') { throw "INVALID_JOB_ID: $jobId" }
        $resultPath=Join-Path $outbox ($jobId + '.json')
        if (-not (Test-Path -LiteralPath $resultPath)) {
            $jobLog=Join-Path $LogsDir ($jobId + '.log')
            $started=Get-Date
            try {
                $data=Invoke-Job $job $jobLog
                $result=[ordered]@{
                    schema='blackgold.project-runner.result.v1'
                    id=$jobId
                    action=[string]$job.action
                    project=[string]$job.project
                    status='success'
                    started_at=$started.ToString('o')
                    finished_at=(Get-Date -Format o)
                    data=$data
                    error=$null
                }
            } catch {
                $result=[ordered]@{
                    schema='blackgold.project-runner.result.v1'
                    id=$jobId
                    action=[string]$job.action
                    project=[string]$job.project
                    status='error'
                    started_at=$started.ToString('o')
                    finished_at=(Get-Date -Format o)
                    data=$null
                    error=$_.Exception.Message
                }
            }
            Write-JsonFile $result $resultPath
        }
    }

    Write-Heartbeat
    Publish-ControlChanges
}
finally {
    if ($LockStream) { $LockStream.Dispose() }
}
