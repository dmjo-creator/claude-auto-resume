# -----------------------------------------------------------------------------
# claude 를 실제로 띄우는 곳 (윈도우) — **여기 하나뿐이다**
#
#     powershell -ExecutionPolicy Bypass -File 재시작설정\win\resume-claude.ps1 <워크스페이스 폴더>
#
# 부르는 쪽
#   ① 각 폴더의 .vscode\tasks.json (폴더를 열 때)  ← sync.ps1 이 심어 둔 발판
#   ② resume-all.ps1 의 대비책 (①이 안 뜨면 새 창으로)
#
# 규칙
#   · 폴더를 열면 항상 띄운다. 끄려면 상태\<폴더명>.끔 또는 상태\.전체끔
#   · 이미 살아 있으면 새로 띄우지 않는다
#   · 대화는 "그 폴더의 것 중 가장 최근" 을 이어받는다
#   · claude 는 워크스페이스 폴더에서 띄운다 (대화 이력이 폴더별이다)
#
# 권한 (2026-09-08)
#   자동재개는 사람이 안 보는 사이에 뜬다. 권한을 물으면 아무도 답하지 않아
#   claude 가 도구를 하나도 못 쓴 채 멈춘다. 그래서 묻지 않고 실행하도록 띄운다.
#   (묻게 하고 싶으면 아래 & $claude 줄에서 --dangerously-skip-permissions 를 지운다.)
# -----------------------------------------------------------------------------
param([Parameter(Mandatory = $true)][string]$Workspace)
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not (Test-Path -LiteralPath $Workspace)) { Write-Host "[!] 폴더가 없다: $Workspace"; exit 1 }
$ws = (Get-Item -LiteralPath $Workspace).FullName.TrimEnd('\')
$ws = Get-NormPath $ws
$name = Get-WsName $ws
$mark = Join-Path $STATE "$name.표식"

Write-JLog 'called' $name 'resume-claude 가 불렸다'

if ((Test-Path -LiteralPath (Join-Path $STATE '.전체끔')) -or (Test-Path -LiteralPath (Join-Path $STATE "$name.끔"))) {
    Write-Host "(자동 실행이 꺼져 있다 — 재시작설정\상태\ 의 .전체끔 또는 $name.끔 을 지우면 켜진다)"
    Write-JLog 'off' $name '꺼 둠'; exit 0
}

if (Test-ClaudeAlive $ws) {
    Write-Host "(claude 가 이미 떠 있다 — pid $CLAUDE_PID. 새로 띄우지 않는다)"
    Write-JLog 'skipped' $name "이미 실행 중 pid $CLAUDE_PID"; exit 0
}

$why = '폴더를 열었다'
if (Test-Path -LiteralPath $mark) { $why = (Get-Content -LiteralPath $mark -Raw -Encoding UTF8).Trim(); Remove-Item -LiteralPath $mark -Force -ErrorAction SilentlyContinue }

$claude = Get-ClaudePath
if (-not $claude) {
    Write-Host '[!] claude 를 찾지 못했다. 이 창에서 직접:  claude --continue'
    Write-Host '    (설치: https://claude.ai/download 또는  npm i -g @anthropic-ai/claude-code)'
    Write-JLog 'fail' $name 'claude 없음'
    Read-Host '엔터를 누르면 닫는다' | Out-Null
    exit 0
}

# 이 PowerShell 이 claude 를 앞에 두고 기다린다 → 이 PID 가 살아 있으면 claude 가 살아 있는 것이다
Set-Content -LiteralPath (Join-Path $STATE "$name.pid") -Value $PID -Encoding ASCII

$promptFile = Join-Path $PROMPTS "$name.txt"
if (-not (Test-Path -LiteralPath $promptFile)) { $promptFile = Join-Path $PROMPTS '_기본.txt' }
$prompt = ''
if (Test-Path -LiteralPath $promptFile) { $prompt = (Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8).Trim() }

$sel = Select-Session $ws
Write-Host "===== 작업 자동 재개 · $name ($why) ====="
Write-Host "  폴더: $ws"
Set-Location -LiteralPath $ws
try {
    if ($sel.Mode -eq 'resume') {
        Write-Host "  대화: $($sel.Id) (이어받기)"
        Write-JLog 'resume' $name "$why · resume $($sel.Id.Substring(0,8))"
        & $claude --dangerously-skip-permissions --resume $sel.Id $prompt
    } else {
        Write-Host '  대화: 이력 없음 — 새로 시작'
        Write-JLog 'resume' $name "$why · new"
        & $claude --dangerously-skip-permissions $prompt
    }
} finally {
    Remove-Item -LiteralPath (Join-Path $STATE "$name.pid") -Force -ErrorAction SilentlyContinue
}
