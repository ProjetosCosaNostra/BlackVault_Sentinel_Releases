$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RunnerVersion = '1.2.2'
$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$ConfigPath = Join-Path $Base 'projects.json'
$ProjectFilter = [string]$env:BLACKGOLD_PROJECT_FILTER
if ([string]::IsNullOrWhiteSpace($ProjectFilter)) { $ProjectFilter = '' }
$InstanceKey = if ($ProjectFilter) { $ProjectFilter } else { 'default' }
$ControlRepo = Join-Path $Base ('control-' + $InstanceKey)
$LogsDir = Join-Path $Base ('logs\' + $InstanceKey)
$LockPath = Join-Path $Base ('runner.' + $InstanceKey + '.lock')
$Branch = 'blackgold-project-runner-v1'
$ControlUrl = 'https://github.com/ProjetosCosaNostra/BlackVault_Sentinel.git'
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
        if (Test-Path -LiteralPath $ControlRepo) {
            Remove-Item -LiteralPath $ControlRepo -Recurse -Force -ErrorAction SilentlyContinue
        }
        & $git clone --branch $Branch --single-branch $ControlUrl $ControlRepo | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'CONTROL_CLONE_FAILED' }
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
    & $git -C $ControlRepo commit -m ("runner: publish " + $InstanceKey + " " + (Get-Date -Format 'yyyyMMdd-HHmmss')) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CONTROL_COMMIT_FAILED' }
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        & $git -C $ControlRepo pull --rebase origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) {
            if ($attempt -eq 4) { throw 'CONTROL_REBASE_FAILED' }
            Start-Sleep -Seconds (2 * $attempt)
            continue
        }
        & $git -C $ControlRepo push origin $Branch | Out-Null
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -lt 4) { Start-Sleep -Seconds (2 * $attempt) }
    }
    throw 'CONTROL_PUSH_FAILED_AFTER_RETRY'
}
function Get-AndroidRoot([object]$Project) {
    if (-not $Project.android_project) { throw "ANDROID_PROJECT_NOT_CONFIGURED: $($Project.id)" }
    $root = Join-Path $Project.root $Project.android_project
    if (-not (Test-Path -LiteralPath $root)) { throw "ANDROID_PROJECT_NOT_FOUND: $root" }
    return $root
}

function Invoke-NativeLogged([string]$FilePath,[string[]]$ArgumentList,[string]$LogPath,[switch]$Append) {
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ($Append) {
            & $FilePath @ArgumentList *>> $LogPath
        }
        else {
            & $FilePath @ArgumentList *> $LogPath
        }
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Invoke-GradleTask([object]$Project,[string]$Task,[string]$LogPath) {
    $androidRoot = Get-AndroidRoot $Project
    $wrapper = Join-Path $androidRoot 'gradlew.bat'
    $cmd = $null
    Push-Location $androidRoot
    try {
        if (Test-Path -LiteralPath $wrapper) {
            $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
            $commandLine = 'call "' + $wrapper + '" --no-daemon ' + $Task
            $code = Invoke-NativeLogged -FilePath $cmdExe -ArgumentList @('/d','/s','/c',$commandLine) -LogPath $LogPath
        } else {
            $cmd = Get-Command gradle.bat -ErrorAction SilentlyContinue
            if (-not $cmd) { $cmd = Get-Command gradle -ErrorAction SilentlyContinue }
            if (-not $cmd) { throw 'GRADLE_NOT_FOUND' }
            $code = Invoke-NativeLogged -FilePath $cmd.Source -ArgumentList @('--no-daemon',$Task) -LogPath $LogPath
        }
    } finally {
        Pop-Location
    }
    if ($code -ne 0) { throw "GRADLE_FAILED_$code : $Task" }
}

function Find-LatestDebugApk([object]$Project) {
    $androidRoot = Get-AndroidRoot $Project
    $outputs = Join-Path $androidRoot 'app\build\outputs'
    if (-not (Test-Path -LiteralPath $outputs)) {
        throw "BUILD_OUTPUTS_NOT_FOUND: $outputs"
    }

    $candidates = @(Get-ChildItem -LiteralPath $outputs -Filter '*.apk' -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '(?i)[\\/]androidTest[\\/]' -and
        $_.Name -notmatch '(?i)androidTest'
    })

    if (-not $candidates.Count) {
        throw "APK_NOT_FOUND_RECURSIVE: $outputs"
    }

    $ranked = foreach ($item in $candidates) {
        $priority = if ($item.FullName -match '(?i)[\\/]debug[\\/]' -or $item.Name -match '(?i)debug') { 0 } else { 1 }
        [pscustomobject]@{ File=$item; Priority=$priority; Time=$item.LastWriteTimeUtc }
    }
    $apk = $ranked | Sort-Object Priority,@{Expression='Time';Descending=$true} | Select-Object -First 1
    return $apk.File.FullName
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
    $captureLog = Join-Path $LogsDir ($JobId + '.capture.log')
    $png = Join-Path $localDir ($JobId + '.png')
    $remote = '/sdcard/blackgold_runner.png'
    $shotCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','screencap','-p',$remote) -LogPath $captureLog
    if ($shotCode -ne 0) { throw 'SCREENSHOT_CAPTURE_FAILED' }
    $pullCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'pull',$remote,$png) -LogPath $captureLog -Append
    if ($pullCode -ne 0) { throw 'SCREENSHOT_PULL_FAILED' }
    [void](Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','rm',$remote) -LogPath $captureLog -Append)

    $size = (Get-Item -LiteralPath $png).Length
    if ($size -gt 2097152) { throw "SCREENSHOT_TOO_LARGE: $size" }
    $outbox = Join-Path $ControlRepo $OutboxRel
    New-Item -ItemType Directory -Force -Path $outbox | Out-Null
    $b64Path = Join-Path $outbox ($JobId + '.screenshot.b64')
    [IO.File]::WriteAllText($b64Path,[Convert]::ToBase64String([IO.File]::ReadAllBytes($png)),[Text.UTF8Encoding]::new($false))

    $xmlRemote = '/sdcard/blackgold_runner.xml'
    $xmlLocal = Join-Path $outbox ($JobId + '.uiautomator.xml')
    $dumpCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','uiautomator','dump',$xmlRemote) -LogPath $captureLog -Append
    if ($dumpCode -eq 0) {
        $xmlPullCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'pull',$xmlRemote,$xmlLocal) -LogPath $captureLog -Append
        if ($xmlPullCode -eq 0) {
            [void](Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','rm',$xmlRemote) -LogPath $captureLog -Append)
        }
    }
    return [ordered]@{
        serial = $serial
        local_png = $png
        screenshot_b64 = ($OutboxRel + '\' + $JobId + '.screenshot.b64')
        uiautomator_xml = $(if (Test-Path -LiteralPath $xmlLocal) { $OutboxRel + '\' + $JobId + '.uiautomator.xml' } else { $null })
        sha256 = (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes = $size
        capture_log = $captureLog
    }
}

function Invoke-VisualGate([object]$Project,[object]$Job,[string]$JobLog) {
    Add-Type -AssemblyName System.Drawing

    $goldenRel = [string]$Job.args.golden_path
    if (-not $goldenRel) { throw 'VISUAL_GATE_GOLDEN_PATH_MISSING' }

    $goldenPath = Join-Path $Project.root $goldenRel
    if (-not (Test-UnderRoot $goldenPath $Project.root)) { throw 'VISUAL_GATE_GOLDEN_OUTSIDE_PROJECT' }
    if (-not (Test-Path -LiteralPath $goldenPath)) { throw "VISUAL_GATE_GOLDEN_NOT_FOUND: $goldenPath" }

    $serial = Start-TargetEmulator $Project
    $adb = Get-Adb

    if ($Job.args.ensure_launch) {
        if (-not $Project.application_id) { throw 'VISUAL_GATE_APPLICATION_ID_NOT_CONFIGURED' }
        $activity = if ($Job.args.activity) { [string]$Job.args.activity } else { '.MainActivity' }
        [void](Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','am','force-stop',([string]$Project.application_id)) -LogPath $JobLog)
        $component = ([string]$Project.application_id) + '/' + $activity
        $launchCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','am','start','-W','-n',$component) -LogPath $JobLog -Append
        if ($launchCode -ne 0) { throw "VISUAL_GATE_APP_LAUNCH_FAILED_$launchCode" }
        Start-Sleep -Seconds 2
    }

    $captureDir = Join-Path $Base 'captures'
    [IO.Directory]::CreateDirectory($captureDir) | Out-Null

    $runtimePath = Join-Path $captureDir (([string]$Job.id) + '.visual-runtime.png')
    $remote = '/sdcard/blackgold_visual_gate.png'
    $captureLog = Join-Path $LogsDir (([string]$Job.id) + '.visual-gate.log')

    $shotCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','screencap','-p',$remote) -LogPath $captureLog
    if ($shotCode -ne 0) { throw 'VISUAL_GATE_CAPTURE_FAILED' }

    $pullCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'pull',$remote,$runtimePath) -LogPath $captureLog -Append
    if ($pullCode -ne 0) { throw 'VISUAL_GATE_PULL_FAILED' }
    [void](Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','rm',$remote) -LogPath $captureLog -Append)

    $gold = [System.Drawing.Bitmap]::FromFile($goldenPath)
    $runtime = [System.Drawing.Bitmap]::FromFile($runtimePath)
    try {
        $cropX = if ($null -ne $Job.args.crop_x) { [int]$Job.args.crop_x } else { 0 }
        $cropY = if ($null -ne $Job.args.crop_y) { [int]$Job.args.crop_y } else { 0 }
        $width = if ($null -ne $Job.args.width) { [int]$Job.args.width } else { $gold.Width }
        $height = if ($null -ne $Job.args.height) { [int]$Job.args.height } else { $gold.Height }
        $channelTolerance = if ($null -ne $Job.args.channel_tolerance) { [int]$Job.args.channel_tolerance } else { 2 }
        $maxMismatchRatio = if ($null -ne $Job.args.max_mismatch_ratio) { [double]$Job.args.max_mismatch_ratio } else { 0.002 }

        if ($gold.Width -ne $width -or $gold.Height -ne $height) {
            throw ("VISUAL_GATE_GOLDEN_DIMENSION_MISMATCH: golden=" + $gold.Width + "x" + $gold.Height + " expected=" + $width + "x" + $height)
        }
        if (($cropX + $width) -gt $runtime.Width -or ($cropY + $height) -gt $runtime.Height) {
            throw ("VISUAL_GATE_RUNTIME_TOO_SMALL: runtime=" + $runtime.Width + "x" + $runtime.Height)
        }

        $gold32 = [System.Drawing.Bitmap]::new($width,$height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $run32 = [System.Drawing.Bitmap]::new($width,$height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $diff = [System.Drawing.Bitmap]::new($width,$height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

        try {
            $gg=[System.Drawing.Graphics]::FromImage($gold32)
            $rg=[System.Drawing.Graphics]::FromImage($run32)
            try {
                $gg.DrawImage($gold,0,0,$width,$height)
                $srcRect = [System.Drawing.Rectangle]::new($cropX,$cropY,$width,$height)
                $dstRect = [System.Drawing.Rectangle]::new(0,0,$width,$height)
                $rg.DrawImage($runtime,$dstRect,$srcRect,[System.Drawing.GraphicsUnit]::Pixel)
            } finally {
                $gg.Dispose()
                $rg.Dispose()
            }

            $rect = [System.Drawing.Rectangle]::new(0,0,$width,$height)
            $gData=$null
            $rData=$null
            $dData=$null
            $gData=$gold32.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $rData=$run32.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $dData=$diff.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::WriteOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

            try {
                $bytes=[Math]::Abs($gData.Stride) * $height
                $ga=New-Object byte[] $bytes
                $ra=New-Object byte[] $bytes
                $da=New-Object byte[] $bytes
                [Runtime.InteropServices.Marshal]::Copy($gData.Scan0,$ga,0,$bytes)
                [Runtime.InteropServices.Marshal]::Copy($rData.Scan0,$ra,0,$bytes)

                [long]$mismatch=0
                [long]$sumDelta=0
                [int]$maxDelta=0

                for($yy=0;$yy -lt $height;$yy++){
                    $row=$yy * [Math]::Abs($gData.Stride)
                    for($xx=0;$xx -lt $width;$xx++){
                        $i=$row + ($xx*4)
                        $db=[Math]::Abs([int]$ga[$i]-[int]$ra[$i])
                        $dg=[Math]::Abs([int]$ga[$i+1]-[int]$ra[$i+1])
                        $dr=[Math]::Abs([int]$ga[$i+2]-[int]$ra[$i+2])
                        $pixelMax=[Math]::Max($dr,[Math]::Max($dg,$db))
                        $sumDelta += ($dr+$dg+$db)
                        if($pixelMax -gt $maxDelta){$maxDelta=$pixelMax}
                        if($pixelMax -gt $channelTolerance){
                            $mismatch++
                            $da[$i]=0
                            $da[$i+1]=0
                            $da[$i+2]=255
                            $da[$i+3]=255
                        } else {
                            $da[$i]=0
                            $da[$i+1]=0
                            $da[$i+2]=0
                            $da[$i+3]=0
                        }
                    }
                }

                [Runtime.InteropServices.Marshal]::Copy($da,0,$dData.Scan0,$bytes)

                $pixels=[double]($width*$height)
                $ratio=[double]$mismatch/$pixels
                $mean=[double]$sumDelta/($pixels*3.0)
                $pass=($ratio -le $maxMismatchRatio)

                $outbox=Join-Path $ControlRepo $OutboxRel
                [IO.Directory]::CreateDirectory($outbox) | Out-Null
                $runtimeOut=Join-Path $outbox (([string]$Job.id)+'.runtime.png')
                $diffOut=Join-Path $outbox (([string]$Job.id)+'.diff.png')
                [IO.File]::Copy($runtimePath,$runtimeOut,$true)
                $diff.Save($diffOut,[System.Drawing.Imaging.ImageFormat]::Png)

                return [ordered]@{
                    pass=$pass
                    serial=$serial
                    golden=$goldenRel
                    golden_sha256=(Get-FileHash -LiteralPath $goldenPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    runtime_sha256=(Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
                    width=$width
                    height=$height
                    crop_x=$cropX
                    crop_y=$cropY
                    channel_tolerance=$channelTolerance
                    mismatch_pixels=$mismatch
                    mismatch_ratio=$ratio
                    mean_abs_channel_delta=$mean
                    max_channel_delta=$maxDelta
                    max_mismatch_ratio=$maxMismatchRatio
                    runtime_png=($OutboxRel + '\' + ([string]$Job.id) + '.runtime.png')
                    diff_png=($OutboxRel + '\' + ([string]$Job.id) + '.diff.png')
                    log=$captureLog
                }
            } finally {
                if($gData){$gold32.UnlockBits($gData)}
                if($rData){$run32.UnlockBits($rData)}
                if($dData){$diff.UnlockBits($dData)}
            }
        } finally {
            if($gold32){$gold32.Dispose()}
            if($run32){$run32.Dispose()}
            if($diff){$diff.Dispose()}
        }
    } finally {
        $gold.Dispose()
        $runtime.Dispose()
    }
}

function Apply-Patch([object]$Project,[object]$Job,[string]$JobLog) {
    $payloadRel = if ($Job.args.payload_dir) { [string]$Job.args.payload_dir } else { "project_runner\payloads\$($Job.id)" }
    $payloadRoot = Normalize-Path (Join-Path $ControlRepo $payloadRel)
    $controlFull = Normalize-Path $ControlRepo
    if (-not (Test-UnderRoot $payloadRoot $controlFull)) { throw 'PAYLOAD_OUTSIDE_CONTROL_REPO' }
    if (-not (Test-Path -LiteralPath $payloadRoot)) { throw "PAYLOAD_NOT_FOUND: $payloadRel" }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = Join-Path $Base ("backups\$($Project.id)\$timestamp")
    $backupFiles = Join-Path $backup 'files'
    [IO.Directory]::CreateDirectory($backupFiles) | Out-Null

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
                [IO.File]::Copy($destination, $backupFile, $true)
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
            if ($rec.existed) {
                $restoreDir = Split-Path -Parent $rec.destination
                if ($restoreDir) { [IO.Directory]::CreateDirectory($restoreDir) | Out-Null }
                [IO.File]::Copy($rec.backup, $rec.destination, $true)
            }
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
            if ($project.id -eq 'junior_resolve') { throw 'JUNIOR_RESOLVE_GENERIC_BUILD_BLOCKED_USE_RECOVERY' }
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
            if ($project.id -eq 'junior_resolve') { throw 'JUNIOR_RESOLVE_GENERIC_INSTALL_BLOCKED_USE_RECOVERY' }
            $serial=Start-TargetEmulator $project
            $apk=Find-LatestDebugApk $project
            $adb=Get-Adb
            $installCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'install','-r',$apk) -LogPath $JobLog
            if ($installCode -ne 0) { throw "ADB_INSTALL_FAILED_$installCode" }
            return [ordered]@{ serial=$serial; apk=$apk; log=$JobLog }
        }
        'launch_app' {
            $project=Get-Project ([string]$Job.project)
            if ($project.id -eq 'junior_resolve') { throw 'JUNIOR_RESOLVE_DIRECT_LAUNCH_BLOCKED_USE_RECOVERY' }
            if (-not $project.application_id) { throw 'APPLICATION_ID_NOT_CONFIGURED' }
            $serial=Start-TargetEmulator $project
            $adb=Get-Adb
            $launchCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','monkey','-p',([string]$project.application_id),'-c','android.intent.category.LAUNCHER','1') -LogPath $JobLog
            if ($launchCode -ne 0) { throw "APP_LAUNCH_FAILED_$launchCode" }
            return [ordered]@{ serial=$serial; application_id=$project.application_id; log=$JobLog }
        }
        'screenshot' {
            $project=Get-Project ([string]$Job.project)
            return (Capture-Screenshot $project ([string]$Job.id))
        }
        'build_install_launch_screenshot' {
            $project=Get-Project ([string]$Job.project)
            if ($project.id -eq 'junior_resolve') { throw 'JUNIOR_RESOLVE_GENERIC_PIPELINE_BLOCKED_USE_RECOVERY' }
            Invoke-GradleTask $project ':app:assembleDebug' $JobLog
            $serial=Start-TargetEmulator $project
            $apk=Find-LatestDebugApk $project
            $adb=Get-Adb
            $installCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'install','-r',$apk) -LogPath $JobLog
            if ($installCode -ne 0) { throw "ADB_INSTALL_FAILED_$installCode" }
            $launchCode = Invoke-NativeLogged -FilePath $adb -ArgumentList @('-s',$serial,'shell','monkey','-p',([string]$project.application_id),'-c','android.intent.category.LAUNCHER','1') -LogPath $JobLog -Append
            if ($launchCode -ne 0) { throw "APP_LAUNCH_FAILED_$launchCode" }
            Start-Sleep -Seconds 3
            $shot=Capture-Screenshot $project ([string]$Job.id)
            return [ordered]@{ apk=$apk; serial=$serial; screenshot=$shot; log=$JobLog }
        }
        'visual_gate' {
            $project=Get-Project ([string]$Job.project)
            return (Invoke-VisualGate $project $Job $JobLog)
        }
        'apply_patch' {
            $project=Get-Project ([string]$Job.project)
            if ($project.id -eq 'junior_resolve') { throw 'JUNIOR_RESOLVE_GENERIC_PATCH_BLOCKED_USE_RECOVERY' }
            return (Apply-Patch $project $Job $JobLog)
        }
        'junior_recovery_diagnostic' {
            $project=Get-Project ([string]$Job.project)
            if ($project.id -ne 'junior_resolve') { throw 'JUNIOR_RECOVERY_DIAGNOSTIC_PROJECT_MISMATCH' }

            $snapshotRoot = 'E:\Junior_Resolve__RECOVERY_SNAPSHOTS'
            if (-not (Test-Path -LiteralPath $snapshotRoot)) { throw "JR_RECOVERY_SNAPSHOT_ROOT_NOT_FOUND: $snapshotRoot" }

            $failure = Get-ChildItem -LiteralPath $snapshotRoot -Filter 'recovery-android-node-failure.json' -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if (-not $failure) { throw 'JR_RECOVERY_FAILURE_RECEIPT_NOT_FOUND' }

            $failureRaw = Get-Content -LiteralPath $failure.FullName -Raw
            $failureObj = $failureRaw | ConvertFrom-Json
            $logPath = [string]$failureObj.log
            if (-not $logPath) { throw 'JR_RECOVERY_FAILURE_LOG_PATH_MISSING' }
            if (-not (Test-UnderRoot $logPath $snapshotRoot)) { throw "JR_RECOVERY_LOG_OUTSIDE_SNAPSHOT_ROOT: $logPath" }

            $tail = @()
            if (Test-Path -LiteralPath $logPath) {
                $tail = @(Get-Content -LiteralPath $logPath -Tail 220)
            }

            $failOnly = @($tail | Where-Object {
                $_ -match '^FAIL\s' -or
                $_ -match '^===== JR RECOVERY FAILURES' -or
                $_ -match '^===== END JR RECOVERY FAILURES' -or
                $_ -match '^Error:' -or
                $_ -match '^> '
            })

            return [ordered]@{
                failure_receipt = $failure.FullName
                failure_error = [string]$failureObj.error
                log = $logPath
                failure_lines = @($failOnly)
                log_tail = @($tail)
            }
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
        project_filter=$ProjectFilter
        instance_key=$InstanceKey
        projects=@($cfg.projects | ForEach-Object { $_.id })
    }
    Write-JsonFile $value (Join-Path $hbDir (($env:COMPUTERNAME) + '-' + $InstanceKey + '.json'))
}

try {
    Sync-ControlRepo
    Write-Heartbeat

    $inbox = Join-Path $ControlRepo $InboxRel
    $outbox = Join-Path $ControlRepo $OutboxRel
    New-Item -ItemType Directory -Force -Path $inbox,$outbox | Out-Null

    $jobFile = $null
    foreach ($candidate in @(Get-ChildItem -LiteralPath $inbox -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $candidateJob = Read-JsonFile $candidate.FullName
            $candidateId = [string]$candidateJob.id
            $candidateProject = [string]$candidateJob.project
            if ($candidateId -notmatch '^[A-Za-z0-9._-]+$') { continue }
            if ($ProjectFilter -and $candidateProject -ne $ProjectFilter) { continue }
            $candidateResult = Join-Path $outbox ($candidateId + '.json')
            if (-not (Test-Path -LiteralPath $candidateResult)) {
                $jobFile = $candidate
                break
            }
        }
        catch {
            continue
        }
    }

    if ($jobFile) {
        $job = Read-JsonFile $jobFile.FullName
        $jobId = [string]$job.id
        if ($jobId -notmatch '^[A-Za-z0-9._-]+$') { throw "INVALID_JOB_ID: $jobId" }

        $resultPath = Join-Path $outbox ($jobId + '.json')
        if (-not (Test-Path -LiteralPath $resultPath)) {
            $jobLog = Join-Path $LogsDir ($jobId + '.log')
            $started = Get-Date
            try {
                $data = Invoke-Job $job $jobLog
                $result = [ordered]@{
                    schema = 'blackgold.project-runner.result.v1'
                    id = $jobId
                    action = [string]$job.action
                    project = [string]$job.project
                    status = 'success'
                    started_at = $started.ToString('o')
                    finished_at = (Get-Date -Format o)
                    data = $data
                    error = $null
                }
            }
            catch {
                $result = [ordered]@{
                    schema = 'blackgold.project-runner.result.v1'
                    id = $jobId
                    action = [string]$job.action
                    project = [string]$job.project
                    status = 'error'
                    started_at = $started.ToString('o')
                    finished_at = (Get-Date -Format o)
                    data = $null
                    error = $_.Exception.Message
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
