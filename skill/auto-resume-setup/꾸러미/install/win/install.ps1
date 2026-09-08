# -----------------------------------------------------------------------------
# 클로드코드 자동재개 — 설치 (윈도우)
#
#     powershell -ExecutionPolicy Bypass -File install\win\install.ps1 [-Root <폴더>] [-NoRegister] [-Quiet]
#
# 하는 일
#   1) 워크스페이스 루트를 정한다 (기본 %USERPROFILE%\클로드코드, 없으면 만든다)
#   2) 루트 아래 '재시작설정' 폴더로 payload 를 복사한다 (설정·상태는 지킨다)
#   3) 설정.txt 의 루트를 이 PC 경로로 채운다
#   4) VS Code 의 자동 작업 허용을 켠다 (task.allowAutomaticTasks = on)
#   5) 모든 워크스페이스에 발판·규칙을 심는다 (sync.ps1)
#   6) 작업 스케줄러에 2개를 등록한다 — 로그인 때 재개 · 회선 감시
#   7) 루트에 '재시작.cmd' 바로가기를 둔다
#
# 관리자 권한은 필요 없다. 작업은 로그인한 사용자 것으로 등록된다.
# -----------------------------------------------------------------------------
param([string]$Root = '', [switch]$NoRegister, [switch]$Quiet)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
function Say { param($m) if (-not $Quiet) { Write-Host $m } }

$HERE = $PSScriptRoot
$PKG  = (Resolve-Path (Join-Path $HERE '..\..')).Path
$PAYLOAD = Join-Path $PKG 'payload'
$TASK_RESUME   = 'ClaudeCode-자동재개'
$TASK_NETWATCH = 'ClaudeCode-회선감시'

Write-Host '==============================================================='
Write-Host '  클로드코드 자동재개 설치 (윈도우)'
Write-Host '==============================================================='
Write-Host ''

# ── 0) 준비물 점검 ───────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host '[!] PowerShell 5 이상이 필요하다 (윈도우 10/11 기본).'; exit 1
}
$code = $null
foreach ($pair in @(@($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\Code.exe'),
                    @(${env:ProgramFiles}, 'Microsoft VS Code\Code.exe'))) {
    if (-not $pair[0]) { continue }
    $c = Join-Path $pair[0] $pair[1]
    if (Test-Path -LiteralPath $c) { $code = $c; break }
}
if (-not $code) { Write-Host '[·] VS Code 가 안 보인다 — 나중에 설치해도 된다 (그때까진 새 창으로 뜬다).' }
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host '[·] claude 명령을 못 찾았다 — 나중에 설치해도 된다 (설치 자체는 끝까지 진행한다).'
}

# ── 1) 워크스페이스 루트 ─────────────────────────────────────────────────────
$defaultRoot = Join-Path $env:USERPROFILE '클로드코드'
if (-not $Root) {
    if ([Environment]::UserInteractive -and -not $Quiet) {
        Write-Host '워크스페이스들이 들어 있는(또는 앞으로 들어갈) 폴더를 정한다.'
        $ans = Read-Host "  그냥 엔터를 누르면: $defaultRoot"
        $Root = if ($ans) { $ans } else { $defaultRoot }
    } else {
        # ★ 비대화형(자동화)인데 -Root 지정이 없으면 멈춘다. 조용히 기본 경로에 설치하지 않는다 (2026-09-08 사고).
        Write-Host '[!] 설치 대상이 지정되지 않았다. 비대화형 실행은 -Root <폴더> 를 명시해야 한다.'; exit 1
    }
}
$Root = [Environment]::ExpandEnvironmentVariables($Root)
if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
$Root = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
$Root = $Root.Normalize([Text.NormalizationForm]::FormC)
$CFG = Join-Path $Root '재시작설정'
Write-Host ''
Say "  루트      : $Root"
Say "  설치 위치 : $CFG"
Write-Host ''

# ── 2) 복사 ─────────────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $CFG)) { New-Item -ItemType Directory -Path $CFG -Force | Out-Null }
$keptConfig = $null
$cfgTxt = Join-Path $CFG '설정.txt'
if (Test-Path -LiteralPath $cfgTxt) { $keptConfig = Get-Content -LiteralPath $cfgTxt -Raw -Encoding UTF8 }

foreach ($item in @('lib.sh','sync.sh','resume_all.sh','resume_claude.sh','netwatch.sh','재시작.command','README.md','win')) {
    $src = Join-Path $PAYLOAD $item
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $CFG $item
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
}
foreach ($d in @('상태','프롬프트')) {
    $dd = Join-Path $CFG $d
    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $PAYLOAD $d) -File -Force -ErrorAction SilentlyContinue)) {
        $t = Join-Path $dd $f.Name
        if (-not (Test-Path -LiteralPath $t)) { Copy-Item -LiteralPath $f.FullName -Destination $t -Force }
    }
}
Say '  파일 복사 완료'

# ── 3) 설정.txt ─────────────────────────────────────────────────────────────
if ($keptConfig) {
    $new = [regex]::Replace($keptConfig, '(?m)^루트=.*$', ('루트=' + $Root))
    if ($new -notmatch '(?m)^루트=') { $new = $new.TrimEnd("`r","`n") + "`n루트=$Root`n" }
    Set-Content -LiteralPath $cfgTxt -Value $new -Encoding UTF8
    Say '  설정.txt : 이미 있던 것을 지키고 루트만 이 PC 경로로 맞췄다'
} else {
    $t = (Get-Content -LiteralPath (Join-Path $PAYLOAD '설정.txt') -Raw -Encoding UTF8).Replace('__ROOT__', $Root)
    Set-Content -LiteralPath $cfgTxt -Value $t -Encoding UTF8
    Say '  설정.txt : 새로 만들었다'
}

# ── 4) VS Code 자동 작업 허용 ────────────────────────────────────────────────
$s = Join-Path $env:APPDATA 'Code\User\settings.json'
$sd = Split-Path -Parent $s
if (-not (Test-Path -LiteralPath $sd)) { New-Item -ItemType Directory -Path $sd -Force | Out-Null }
if (-not (Test-Path -LiteralPath $s) -or -not (Get-Content -LiteralPath $s -Raw -Encoding UTF8).Trim()) {
    Set-Content -LiteralPath $s -Value "{`n  `"task.allowAutomaticTasks`": `"on`"`n}`n" -Encoding UTF8
    Say '  편집기 설정 : 새로 만들고 자동 작업을 켰다'
} else {
    $txt = Get-Content -LiteralPath $s -Raw -Encoding UTF8
    if ($txt -match '"task\.allowAutomaticTasks"\s*:\s*"on"') {
        Say '  편집기 설정 : 자동 작업 이미 켜져 있다'
    } else {
        Copy-Item -LiteralPath $s -Destination ($s + '.자동재개설치전') -Force
        if ($txt -match '"task\.allowAutomaticTasks"') {
            $txt2 = [regex]::Replace($txt, '"task\.allowAutomaticTasks"\s*:\s*"[^"]*"', '"task.allowAutomaticTasks": "on"')
        } else {
            $i = $txt.IndexOf('{')
            if ($i -lt 0) { $txt2 = $null } else { $txt2 = $txt.Substring(0, $i + 1) + "`n  `"task.allowAutomaticTasks`": `"on`"," + $txt.Substring($i + 1) }
        }
        if ($txt2) { Set-Content -LiteralPath $s -Value $txt2 -Encoding UTF8; Say '  편집기 설정 : 자동 작업을 켰다 (원본은 settings.json.자동재개설치전 로 남겼다)' }
        else { Write-Host '  [!] 편집기 설정 파일을 이해하지 못했다 — 손으로 켤 것' }
    }
}

# ── 5) 발판·규칙 심기 ────────────────────────────────────────────────────────
Write-Host ''
& (Join-Path $CFG 'win\sync.ps1')

# ── 6) 작업 스케줄러 등록 ────────────────────────────────────────────────────
Write-Host ''
if (-not $NoRegister) {
    function Register-One {
        param([string]$Name, [string]$Script, [string[]]$ExtraArgs, [switch]$Restart)
        try {
            $argLine = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',
                         ('"' + (Join-Path $CFG ('win\' + $Script)) + '"')) + $ExtraArgs
            $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($argLine -join ' ') -WorkingDirectory $CFG
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
            $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
            if ($Restart) { $set.RestartInterval = 'PT1M'; $set.RestartCount = 999 }
            $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
            Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $set -Principal $p -Force -ErrorAction Stop | Out-Null
            Write-Host "  자동실행 등록: $Name"
        } catch {
            Write-Host "  [!] 자동실행 등록 실패: $Name — $($_.Exception.Message)"
            Write-Host "      (작업 스케줄러를 열어 '$Name' 을 손으로 만들어도 된다. 설명서에 방법이 있다)"
        }
    }
    Register-One -Name $TASK_RESUME   -Script 'resume-all.ps1' -ExtraArgs @('-Why','"PC 시작"')
    Register-One -Name $TASK_NETWATCH -Script 'netwatch.ps1'   -ExtraArgs @() -Restart
} else {
    Say '  (-NoRegister: 자동실행 등록은 건너뛴다)'
}

# ── 7) 루트 바로가기 ────────────────────────────────────────────────────────
# ★ 배치 파일은 콘솔 코드페이지로 읽힌다. 그래서 chcp 를 넣지 않고 OEM(이 PC 의 코드페이지)으로 쓴다.
#   한글 경로가 깨져 보이면 재시작설정\win\재시작.cmd 를 직접 써도 된다 (그 파일은 순수 ASCII 다).
$cmd = @"
@echo off
title Claude Code restart all
powershell -NoProfile -ExecutionPolicy Bypass -File "$CFG\win\restart.ps1"
echo.
pause
"@
try { Set-Content -LiteralPath (Join-Path $Root '재시작.cmd') -Value $cmd -Encoding OEM -ErrorAction Stop }
catch { Set-Content -LiteralPath (Join-Path $Root '재시작.cmd') -Value $cmd -Encoding Default }

Write-Host ''
Write-Host '==============================================================='
Write-Host '  설치 끝'
Write-Host '==============================================================='
Write-Host "  설정 고치기   : $CFG\설정.txt"
Write-Host "  설명서        : $CFG\README.md"
Write-Host "  손으로 재시작 : $Root\재시작.cmd  (더블클릭)"
Write-Host "  전부 끄기     : $CFG\상태\.전체끔  파일을 만든다"
Write-Host ''
Write-Host '  이제 PC 를 켤 때마다, 그리고 인터넷이 끊겼다 돌아올 때마다'
Write-Host '  워크스페이스 폴더들이 편집기에서 자동으로 열리고 claude 가 이어받는다.'
Write-Host ''
if ([Environment]::UserInteractive -and -not $Quiet) { Read-Host '  엔터를 누르면 닫는다' | Out-Null }
