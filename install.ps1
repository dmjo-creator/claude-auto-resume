# 클로드코드 자동재개 — 윈도우 한 줄 설치 (PowerShell 에서)
#   irm https://raw.githubusercontent.com/dmjo-creator/claude-auto-resume/main/install.ps1 | iex
#   (설치 대상 = 명령을 실행한 현재 폴더)
$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$tmp = Join-Path $env:TEMP ("ccresume_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
Write-Host '저장소를 내려받는다...'
$tgz = Join-Path $tmp 'repo.tgz'
Invoke-WebRequest 'https://github.com/dmjo-creator/claude-auto-resume/archive/refs/heads/main.tar.gz' -OutFile $tgz
tar -xzf $tgz -C $tmp
$kit = Get-ChildItem -Directory (Join-Path $tmp 'claude-auto-resume-*') | Select-Object -First 1
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit.FullName 'kit\install\win\install.ps1') -Root $root
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
