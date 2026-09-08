# 제거 (윈도우) — 자동실행 등록만 지운다. 워크스페이스 파일과 대화는 건드리지 않는다.
#   powershell -ExecutionPolicy Bypass -File install\win\uninstall.ps1 [-All] [-Root <폴더>]
param([switch]$All, [string]$Root = '')
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
Write-Host '===== 클로드코드 자동재개 제거 ====='
foreach ($t in @('ClaudeCode-자동재개','ClaudeCode-회선감시')) {
    try {
        if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction Stop
            Write-Host "  자동실행 해제: $t"
        }
    } catch { Write-Host "  [!] 해제 실패: $t — $($_.Exception.Message)" }
}
if ($All) {
    if (-not $Root) { $Root = Join-Path $env:USERPROFILE '클로드코드' }
    $CFG = Join-Path $Root '재시작설정'
    if (Test-Path -LiteralPath $Root) {
        # 루트 바로 아래 폴더 + 묶음 폴더 안의 하위 폴더까지 훑는다
        $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue)
        $dirs += @($dirs | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue })
        foreach ($d in $dirs) {
            $f = Join-Path $d.FullName '.vscode\tasks.json'
            if ((Test-Path -LiteralPath $f) -and ((Get-Content -LiteralPath $f -Raw -Encoding UTF8) -like '*재시작설정이 만든 파일*')) {
                Remove-Item -LiteralPath $f -Force; Write-Host "  발판 제거: $($d.Name)"
            }
            $c = Join-Path $d.FullName 'CLAUDE.md'
            if ((Test-Path -LiteralPath $c) -and ((Get-Content -LiteralPath $c -Raw -Encoding UTF8) -like '*재시작설정 관리 블록 시작*')) {
                $out = New-Object System.Collections.Generic.List[string]; $skip = $false
                foreach ($l in (Get-Content -LiteralPath $c -Encoding UTF8)) {
                    if ($l -like '<!-- 재시작설정 관리 블록 시작*') { $skip = $true; continue }
                    if ($l -like '<!-- 재시작설정 관리 블록 끝*')   { $skip = $false; continue }
                    if (-not $skip) { $out.Add($l) }
                }
                Set-Content -LiteralPath $c -Value ($out -join "`n") -Encoding UTF8
                Write-Host "  규칙 블록 제거: $($d.Name)"
            }
        }
        Write-Host "  재시작설정 폴더는 남겨 둔다 (로그·설정이 들어 있다): $CFG"
    }
}
Write-Host '  대화 이력(~\.claude)과 작업 파일은 건드리지 않았다.'
Write-Host '===== 끝 ====='
