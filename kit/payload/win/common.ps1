# -----------------------------------------------------------------------------
# 공용 함수 (윈도우) — 모든 윈도우 스크립트가 이 파일을 읽는다.
# 설정은 상위 폴더의 설정.txt 하나뿐이다 (맥과 같은 파일을 쓴다).
# -----------------------------------------------------------------------------
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$script:CFG     = Split-Path -Parent $PSScriptRoot      # 재시작설정 폴더
$script:STATE   = Join-Path $CFG '상태'
$script:PROMPTS = Join-Path $CFG '프롬프트'
foreach ($d in @($STATE, $PROMPTS)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

# ── 설정 읽기 ────────────────────────────────────────────────────────────────
$script:BASE = ''; $script:EXCLUDE = @('data'); $script:CONTAINERS = @('_bundle')
$script:EXTRA = @(); $script:NET_WAIT = 300; $script:OPEN_STAGGER = 4
$script:FOLDEROPEN_WAIT = 30; $script:RESUME_GAP = 120
$script:NET_DOWN_MIN = 30; $script:NET_POLL = 20; $script:MIN_SESSION_BYTES = 20000

function Read-Config {
    $f = Join-Path $CFG '설정.txt'
    if (-not (Test-Path $f)) { Write-Host "[!] 설정 파일이 없다: $f"; return $false }
    foreach ($line in (Get-Content -LiteralPath $f -Encoding UTF8)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#') -or ($t -notmatch '=')) { continue }
        $k = $t.Substring(0, $t.IndexOf('=')).Trim()
        $v = $t.Substring($t.IndexOf('=') + 1).Trim()
        switch ($k) {
            '루트'            { $script:BASE = $v }
            '제외'            { $script:EXCLUDE = @($v -split '\s+' | Where-Object { $_ }) }
            '컨테이너'         { $script:CONTAINERS = @($v -split '\s+' | Where-Object { $_ }) }
            '추가워크스페이스'   { $script:EXTRA = @($v -split '\s+' | Where-Object { $_ }) }
            '회선대기'         { $script:NET_WAIT = [int]$v }
            '창간격'          { $script:OPEN_STAGGER = [int]$v }
            '발판대기'         { $script:FOLDEROPEN_WAIT = [int]$v }
            '재개간격'         { $script:RESUME_GAP = [int]$v }
            '끊김최소'         { $script:NET_DOWN_MIN = [int]$v }
            '확인간격'         { $script:NET_POLL = [int]$v }
            '최소대화크기'      { $script:MIN_SESSION_BYTES = [int]$v }
        }
    }
    if (-not $BASE) { Write-Host "[!] 설정.txt 의 '루트' 가 비어 있다"; return $false }
    return $true
}
if (-not (Read-Config)) { exit 1 }

function Now-Str { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }

# 기록 — 상태\재시작로그.jsonl
function Write-JLog {
    param([string]$Event, [string]$Ws = '', [string]$Note = '')
    $o = '{{"ts":"{0}","event":"{1}","ws":"{2}","note":"{3}"}}' -f `
         (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'), $Event, $Ws, ($Note -replace '"', "'")
    Add-Content -LiteralPath (Join-Path $STATE '재시작로그.jsonl') -Value $o -Encoding UTF8
}

# 경로를 NFC 로 맞춘다 — 한글 폴더이름이 NFD 로 저장돼 있으면 대화 폴더 이름이 어긋난다
function Get-NormPath { param([string]$P) if ($null -eq $P) { return $P } return $P.Normalize([Text.NormalizationForm]::FormC) }

# 워크스페이스 목록 (절대경로, NFC)
function Get-Workspaces {
    $out = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $BASE)) { return $out }
    foreach ($d in (Get-ChildItem -LiteralPath $BASE -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name.StartsWith('.')) { continue }
        if ($EXCLUDE -contains $d.Name) { continue }
        if ($CONTAINERS -contains $d.Name) {
            foreach ($s in (Get-ChildItem -LiteralPath $d.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                if (-not $s.Name.StartsWith('.')) { $out.Add((Get-NormPath $s.FullName)) }
            }
            continue
        }
        $out.Add((Get-NormPath $d.FullName))
    }
    foreach ($e in $EXTRA) { if (Test-Path -LiteralPath $e) { $out.Add((Get-NormPath $e)) } }
    return $out
}

function Get-WsName { param([string]$Ws) return (Split-Path -Leaf (Get-NormPath $Ws)) }

# claude 가 대화를 보관하는 폴더 (~\.claude\projects\<경로의 비영숫자→'-'>)
function Get-ProjDir {
    param([string]$Ws)
    $key = [regex]::Replace((Get-NormPath $Ws), '[^A-Za-z0-9]', '-')
    return (Join-Path (Join-Path $env:USERPROFILE '.claude\projects') $key)
}

# 이어받을 대화 고르기 → @{Mode='resume'; Id='...'} 또는 @{Mode='new'}
#   ★ 대화 폴더는 경로 글자 수만 같으면 겹친다. 그래서 대화 파일 안의 cwd 를 대조해서 고른다.
#   ★ 못 고르면 --continue 가 아니라 새 대화로 간다 (--continue 는 남의 폴더 대화를 물 수 있다).
function Select-Session {
    param([string]$Ws)
    $name = Get-WsName $Ws
    $pinFile = Join-Path $STATE '고정세션.txt'
    $pd = Get-ProjDir $Ws
    if (Test-Path -LiteralPath $pinFile) {
        foreach ($line in (Get-Content -LiteralPath $pinFile -Encoding UTF8)) {
            $t = $line.Trim(); if ($t -eq '' -or $t.StartsWith('#')) { continue }
            $p = $t -split '\s+'
            if ($p.Count -ge 2 -and $p[0] -eq $name -and (Test-Path -LiteralPath (Join-Path $pd ($p[1] + '.jsonl')))) {
                return @{ Mode = 'resume'; Id = $p[1] }
            }
        }
    }
    if (-not (Test-Path -LiteralPath $pd)) { return @{ Mode = 'new' } }
    $wantFull = (Get-Item -LiteralPath $Ws).FullName.TrimEnd('\')
    $best = $null; $bestTime = [datetime]::MinValue
    foreach ($f in (Get-ChildItem -LiteralPath $pd -Filter *.jsonl -File -ErrorAction SilentlyContinue)) {
        if ($f.Length -lt $MIN_SESSION_BYTES) { continue }
        $cwd = $null; $i = 0
        try {
            $reader = [IO.StreamReader]::new($f.FullName, [Text.Encoding]::UTF8)
            while (-not $reader.EndOfStream -and $i -lt 200) {
                $line = $reader.ReadLine(); $i++
                if (-not $line) { continue }
                try { $o = $line | ConvertFrom-Json } catch { continue }
                if ($o.PSObject.Properties.Name -contains 'cwd' -and $o.cwd) { $cwd = [string]$o.cwd; break }
            }
        } catch { continue } finally { if ($reader) { $reader.Dispose() } }
        if (-not $cwd) { continue }
        # 같은 폴더인가 — 대소문자·끝 역슬래시·NFD 차이를 흡수해서 견준다
        try { $cwdFull = (Get-Item -LiteralPath $cwd -ErrorAction Stop).FullName.TrimEnd('\') } catch { continue }
        if ((Get-NormPath $cwdFull) -ne (Get-NormPath $wantFull)) { continue }
        if ($f.LastWriteTime -gt $bestTime) { $bestTime = $f.LastWriteTime; $best = $f }
    }
    if ($best) { return @{ Mode = 'resume'; Id = [IO.Path]::GetFileNameWithoutExtension($best.Name) } }
    return @{ Mode = 'new' }
}

# 그 워크스페이스의 claude 가 살아 있나
#   ① 상태\<폴더>.pid 의 프로세스가 아직 있나 (우리가 띄운 것 — 그 셸이 claude 를 앞에 두고 있다)
#   ② 아니면 명령줄에 그 폴더의 대화ID 가 들어 있는 claude 프로세스가 있나
#   윈도우는 남의 프로세스 작업폴더를 곧바로 볼 수 없다. 그래서 이 두 가지로 판정한다.
$script:CLAUDE_PID = 0
function Test-ClaudeAlive {
    param([string]$Ws)
    $name = Get-WsName $Ws
    $pidFile = Join-Path $STATE "$name.pid"
    if (Test-Path -LiteralPath $pidFile) {
        $pidText = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        $pidNum = 0
        if ([int]::TryParse(($pidText -as [string]), [ref]$pidNum) -and $pidNum -gt 0) {
            $p = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
            if ($p) { $script:CLAUDE_PID = $pidNum; return $true }
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
    $sel = Select-Session $Ws
    if ($sel.Mode -eq 'resume') {
        try {
            $procs = Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='claude.exe'" -ErrorAction Stop
            foreach ($pr in $procs) {
                if ($pr.CommandLine -and $pr.CommandLine -match 'claude' -and $pr.CommandLine -match [regex]::Escape($sel.Id)) {
                    Set-Content -LiteralPath $pidFile -Value $pr.ProcessId -Encoding ASCII
                    $script:CLAUDE_PID = $pr.ProcessId; return $true
                }
            }
        } catch {}
    }
    return $false
}

function Test-Online {
    try {
        $r = Invoke-WebRequest -Uri 'https://www.google.com/generate_204' -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        try { return (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction Stop) } catch { return $false }
    }
}
function Wait-Online {
    param([int]$MaxSec = 300)
    $t = 0
    while ($t -lt $MaxSec) { if (Test-Online) { return $true }; Start-Sleep -Seconds 10; $t += 10 }
    return $false
}

# 이 워크스페이스에서 함께 깨울 작업 스케줄러 작업 (선택) — 상태\서비스.txt
function Get-ServicesFor {
    param([string]$Name)
    $f = Join-Path $STATE '서비스.txt'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    foreach ($line in (Get-Content -LiteralPath $f -Encoding UTF8)) {
        $t = $line.Trim(); if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $p = $t -split '\s+'
        if ($p[0] -eq $Name) { return @($p[1..($p.Count - 1)]) }
    }
    return @()
}

# 지금 돌고 있는 PowerShell 실행 파일 — 새 창을 띄울 때 쓴다
#   'powershell' 이라는 이름에 기대지 않는다 (PowerShell 7 만 깔린 PC 도 있다)
function Get-PSExe {
    try { $p = (Get-Process -Id $PID).Path; if ($p) { return $p } } catch {}
    return 'powershell.exe'
}

# VS Code 실행 파일 찾기
function Get-VSCodePath {
    # 환경변수가 없는 경우(다른 OS·특이한 계정)에도 조용히 넘어가게 하나씩 확인한다
    foreach ($pair in @(@($env:LOCALAPPDATA, 'Programs\Microsoft VS Code\Code.exe'),
                        @(${env:ProgramFiles}, 'Microsoft VS Code\Code.exe'),
                        @(${env:ProgramFiles(x86)}, 'Microsoft VS Code\Code.exe'))) {
        if (-not $pair[0]) { continue }
        $c = Join-Path $pair[0] $pair[1]
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# claude 실행 파일 찾기
function Get-ClaudePath {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($pair in @(@($env:APPDATA, 'npm\claude.cmd'),
                        @($env:USERPROFILE, '.local\bin\claude.exe'),
                        @($env:LOCALAPPDATA, 'Programs\claude\claude.exe'))) {
        if (-not $pair[0]) { continue }
        $c = Join-Path $pair[0] $pair[1]
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}
