# -----------------------------------------------------------------------------
# 전체 재개 (윈도우) — PC 가 켜졌거나 회선이 돌아왔거나 사람이 재시작할 때
#
#     powershell -ExecutionPolicy Bypass -File 재시작설정\win\resume-all.ps1 [-Why 사유] [-Only 폴더명] [-NoWait]
#
# 하는 일
#   0) sync.ps1 — 새로 만든 폴더에도 발판을 심는다
#   1) 회선을 기다린다 (부팅 직후엔 아직 없다)
#   2) (상태\서비스.txt 에 적어 두었다면) 작업 스케줄러 작업을 깨운다
#   3) claude 가 죽어 있는 워크스페이스마다: 표식 → 편집기로 폴더 열기(간격을 둔다)
#   4) 정해진 시간 안에 안 뜨면 새 PowerShell 창으로 직접 띄운다
#
# ★ 발행·전송·배포는 여기서 일어나지 않는다. 창과 claude 만 되살린다.
# ★ 살아 있는 claude 는 건드리지 않는다.
# -----------------------------------------------------------------------------
param([string]$Why = '자동 재개', [string]$Only = '', [switch]$NoWait)
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host "===== $(Now-Str) 전체 재개 ($Why) ====="
Write-JLog 'start' 'all' ("$Why" + $(if ($Only) { " · only $Only" } else { '' }))

# 짧은 시간 안에 두 번 돌지 않는다
$lastFile = Join-Path $STATE '.마지막전체재개'
$last = 0
if (Test-Path -LiteralPath $lastFile) { [int]::TryParse((Get-Content -LiteralPath $lastFile -Raw).Trim(), [ref]$last) | Out-Null }
$nowSec = [int][double]::Parse((Get-Date -UFormat %s))
if (-not $Only -and ($nowSec - $last) -lt $RESUME_GAP) {
    Write-Host "  $RESUME_GAP 초 안에 이미 돌았다 — 건너뛴다"; Write-JLog 'skipped' 'all' 'gap'; exit 0
}
Set-Content -LiteralPath $lastFile -Value $nowSec -Encoding ASCII

& (Join-Path $PSScriptRoot 'sync.ps1') -Quiet

if (-not $NoWait) {
    if (Wait-Online $NET_WAIT) { Write-Host '  회선 정상' }
    else { Write-Host "  [!] $NET_WAIT 초 안에 회선이 안 돌아왔다 — 그래도 진행한다"; Write-JLog 'net' 'all' '대기 실패' }
}

$targets = New-Object System.Collections.Generic.List[string]
foreach ($ws in (Get-Workspaces)) {
    $name = Get-WsName $ws
    if ($Only -and $name -ne $Only) { continue }
    foreach ($t in (Get-ServicesFor $name)) {
        try { Start-ScheduledTask -TaskName $t -ErrorAction Stop; Write-Host "  깨움: $t" } catch {}
    }
    if ((Test-Path -LiteralPath (Join-Path $STATE '.전체끔')) -or (Test-Path -LiteralPath (Join-Path $STATE "$name.끔"))) {
        Write-Host "  $name : 꺼 둠"; continue
    }
    if (Test-ClaudeAlive $ws) { Write-Host "  $name : claude 살아 있음 (pid $CLAUDE_PID) — 그대로 둔다"; continue }
    $targets.Add($ws)
}

if ($targets.Count -eq 0) { Write-Host '  되살릴 것이 없다'; Write-JLog 'done' 'all' 'nothing'; exit 0 }

$code = Get-VSCodePath
if ($code) {
    foreach ($ws in $targets) {
        $name = Get-WsName $ws
        Set-Content -LiteralPath (Join-Path $STATE "$name.표식") -Value ("$(Now-Str) · $Why") -Encoding UTF8
        Write-Host "  편집기로 연다: $name"
        Start-Process -FilePath $code -ArgumentList @($ws) | Out-Null
        Start-Sleep -Seconds $OPEN_STAGGER
    }
    Write-Host "  자동 작업을 $FOLDEROPEN_WAIT 초 기다린다"
    for ($i = 0; $i -lt [int]($FOLDEROPEN_WAIT / 2); $i++) {
        Start-Sleep -Seconds 2
        $all = $true
        foreach ($ws in $targets) { if (-not (Test-ClaudeAlive $ws)) { $all = $false } }
        if ($all) { break }
    }
} else {
    Write-Host '  [!] VS Code 를 못 찾았다 — 새 창으로 띄운다'
}

foreach ($ws in $targets) {
    $name = Get-WsName $ws
    if (Test-ClaudeAlive $ws) { Write-Host "  $name : 편집기 안에서 떴다 (pid $CLAUDE_PID)"; Write-JLog 'done' $name 'vscode'; continue }
    Write-Host "  $name : 안 떴다 — 새 창으로 직접 띄운다"
    Write-JLog 'fallback' $name 'console'
    Start-Process -FilePath (Get-PSExe) -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
        '-File', ('"' + (Join-Path $PSScriptRoot 'resume-claude.ps1') + '"'), ('"' + $ws + '"')) | Out-Null
    Start-Sleep -Seconds 2
}
Write-Host '===== 끝 ====='
