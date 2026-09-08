# -----------------------------------------------------------------------------
# 손으로 전체 재시작 (윈도우) — 편집기를 정상 종료하고 모든 워크스페이스를 되살린다.
#   재시작.cmd 를 더블클릭하면 이 파일이 돈다.
# -----------------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host "===== $(Now-Str) 손으로 재시작 ====="
$procs = Get-Process -Name Code -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host '  편집기를 닫는다'
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch {} }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        if (-not (Get-Process -Name Code -ErrorAction SilentlyContinue)) { break }
    }
    $left = Get-Process -Name Code -ErrorAction SilentlyContinue
    if ($left) { $left | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
}
# 방금 돌았어도 이번엔 사람이 시킨 것이다
Remove-Item -LiteralPath (Join-Path $STATE '.마지막전체재개') -Force -ErrorAction SilentlyContinue

& (Join-Path $PSScriptRoot 'resume-all.ps1') -Why '손으로 재시작' -NoWait

Write-Host ''
Write-Host '  안 뜬 창이 있으면 그 창 터미널에서:  claude --continue'
