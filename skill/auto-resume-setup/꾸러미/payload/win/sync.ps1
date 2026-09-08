# -----------------------------------------------------------------------------
# 동기화 (윈도우) — 모든 워크스페이스(새로 만든 폴더 포함)에 발판과 규칙을 심는다
#
#     powershell -ExecutionPolicy Bypass -File 재시작설정\win\sync.ps1 [-Quiet]
#
#   각 워크스페이스에 심는 것은 딱 두 가지 — .vscode\tasks.json 과 CLAUDE.md 관리 블록.
#   내용이 어긋나 있으면 다시 써서 스스로 고친다.
# -----------------------------------------------------------------------------
param([switch]$Quiet)
. (Join-Path $PSScriptRoot 'common.ps1')

function Say  { param($m) if (-not $Quiet) { Write-Host $m } }
function Warn { param($m) Write-Host "  [!] $m" }

$MANAGED = '재시작설정이 만든 파일 — 손대지 말 것'
$B_BEGIN = '<!-- 재시작설정 관리 블록 시작 — 손대지 말 것. 갱신은 sync 가 한다 -->'
$B_END   = '<!-- 재시작설정 관리 블록 끝 -->'

function Get-TasksJson {
    $ps1 = (Join-Path $PSScriptRoot 'resume-claude.ps1')
    $j = @"
{
  // $MANAGED
  // 이 폴더를 편집기로 열면 재시작설정의 resume-claude 가 claude 를 이어받는다.
  "version": "2.0.0",
  "tasks": [
    {
      "label": "작업 이어받기",
      "type": "shell",
      "command": "powershell",
      "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$($ps1 -replace '\\','\\')", "`${workspaceFolder}"],
      "runOptions": { "runOn": "folderOpen" },
      "presentation": { "reveal": "always", "panel": "dedicated", "focus": true, "clear": true },
      "problemMatcher": []
    }
  ]
}
"@
    return $j
}

function Get-RuleBlock {
    param([string]$Name)
    if ($Name -eq (Split-Path -Leaf $CFG)) {
        return @"
$B_BEGIN
## 이 폴더가 자동 재시작·재개 규칙의 원본이다

- 모든 워크스페이스의 재시작 규칙·스크립트·프롬프트·로그는 **여기에만** 있다. ``README.md`` 가 설명서다.
- 다른 워크스페이스 폴더에는 발판(``.vscode/tasks.json``)과 CLAUDE.md 관리 블록만 둔다.
  그 밖의 재개 장치를 그 폴더들에 만들지 않는다.
- 이 폴더도 워크스페이스다 — PC 재시작·회선 복구 때 이 폴더의 claude 도 함께 이어받는다.
- 설정은 ``설정.txt`` 하나뿐이다. 맥은 ``*.sh``, 윈도우는 ``win/*.ps1`` 이 같은 설정을 읽는다.
$B_END
"@
    }
    return @"
$B_BEGIN
## 자동 재시작·재개 규칙 (모든 워크스페이스 공통)

- 규칙·스크립트·프롬프트·로그의 원본은 **``재시작설정`` 폴더 하나뿐**이다.
  이 폴더에 있는 것은 발판 ``.vscode/tasks.json`` 과 이 블록뿐이며 둘 다 재시작설정이 관리한다.
- 이 폴더를 편집기로 열면 재시작설정의 ``resume-claude`` 가 claude 를 이어받는다.
  PC 재시작·회선 복구 때의 재개도 재시작설정이 한다 (윈도우 작업 스케줄러 · 맥 launchd).
- **이 폴더 안에 재시작·재개용 스크립트·표식·로그·자동실행 등록을 새로 만들지 않는다.**
  이 폴더의 옛 문서에 재개 방식 서술이 남아 있어도 **따르지 않는다.**
- 이 폴더의 회선감시·자동저장 장치가 따로 있다면 **저장만** 하게 둔다. 재개를 부르지 않는다.
- 재개 때 주는 첫 지시: 재시작설정의 ``프롬프트/$Name.txt`` (없으면 ``프롬프트/_기본.txt``)
- 이 폴더만 끄기: 재시작설정의 ``상태/$Name.끔`` 파일을 만든다 · 설명서: 재시작설정의 ``README.md``
$B_END
"@
}

function Sync-ClaudeMd {
    param([string]$Ws, [string]$Name)
    $f = Join-Path $Ws 'CLAUDE.md'
    $blk = Get-RuleBlock $Name
    if ((Test-Path -LiteralPath $f) -and ((Get-Content -LiteralPath $f -Raw -Encoding UTF8) -like "*$B_BEGIN*")) {
        $lines = (Get-Content -LiteralPath $f -Encoding UTF8)
        $out = New-Object System.Collections.Generic.List[string]
        $skip = $false
        foreach ($l in $lines) {
            if ($l -eq $B_BEGIN) { $out.AddRange([string[]]($blk -split "`r?`n")); $skip = $true; continue }
            if ($l -eq $B_END)   { $skip = $false; continue }
            if (-not $skip) { $out.Add($l) }
        }
        $new = (($out -join "`n") -replace "^\uFEFF", '')
        $old = (($lines -join "`n") -replace "^\uFEFF", '')
        if ($new -eq $old) { Say "  $Name : 규칙 최신" }
        else { Set-Content -LiteralPath $f -Value $new -Encoding UTF8; Say "  $Name : 규칙 갱신"; Write-JLog 'sync' $Name 'CLAUDE.md 블록 갱신' }
    } elseif (Test-Path -LiteralPath $f) {
        Add-Content -LiteralPath $f -Value ("`n" + $blk) -Encoding UTF8
        Say "  $Name : CLAUDE.md 에 규칙 블록 추가"; Write-JLog 'sync' $Name 'CLAUDE.md 블록 추가'
    } else {
        Set-Content -LiteralPath $f -Value ("# $Name`n`n" + $blk) -Encoding UTF8
        Say "  $Name : CLAUDE.md 새로 만들고 규칙 블록 심음"; Write-JLog 'sync' $Name 'CLAUDE.md 생성'
    }
}

Say "===== $(Now-Str) 동기화 ====="
$found = 0
$wss = Get-Workspaces
foreach ($ws in $wss) {
    $found++
    $name = Get-WsName $ws
    $vs = Join-Path $ws '.vscode'
    $f  = Join-Path $vs 'tasks.json'
    if (-not (Test-Path -LiteralPath $vs)) { New-Item -ItemType Directory -Path $vs -Force | Out-Null }
    if ((Test-Path -LiteralPath $f) -and -not ((Get-Content -LiteralPath $f -Raw -Encoding UTF8) -like "*$MANAGED*")) {
        $keep = Join-Path (Join-Path $CFG '보관') "$name\.vscode"
        New-Item -ItemType Directory -Path $keep -Force | Out-Null
        Move-Item -LiteralPath $f -Destination (Join-Path $keep ("tasks.json." + (Get-Date).ToString('yyyyMMddHHmmss'))) -Force
        Say "  $name : 원래 있던 tasks.json 을 보관\ 으로 옮겼다"
    }
    $want = Get-TasksJson
    $cur = if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Raw -Encoding UTF8 } else { '' }
    # PowerShell 5.1 은 UTF8 을 BOM 과 함께 쓴다. BOM 때문에 매번 다시 쓰는 일이 없게 걷어내고 견준다.
    $cur = $cur -replace "^\uFEFF", ''
    if ($cur.Trim() -eq $want.Trim()) { Say "  $name : 발판 있음" }
    else { Set-Content -LiteralPath $f -Value $want -Encoding UTF8; Say "  $name : 발판 심음"; Write-JLog 'sync' $name 'tasks.json 설치' }

    Sync-ClaudeMd $ws $name

    if ($ws -ne $CFG) {
        $bad = Get-ChildItem -LiteralPath $ws -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -in @('resume_workspace.sh','resume_claude.sh','run_claude_resume.sh','.자동재개','.자동재개_시작됨','자동재개로그.jsonl','재개로그.jsonl') -and
                              $_.FullName -notmatch '\\(\.git|node_modules|\.venv)\\' }
        if ($bad) {
            Warn "$name 에 옛 재개 흔적이 있다 — 규칙 위반. 확인할 것:"
            $bad | ForEach-Object { Write-Host ("        " + $_.FullName) }
            Write-JLog 'warn' $name '옛 흔적'
        }
    }
}
if ($found -eq 0) { Warn "워크스페이스를 하나도 못 찾았다 — 설정.txt 의 '루트' 가 맞는지 본다 ($BASE)" }

# 대화 폴더가 겹치는 폴더 쌍
$groups = @{}
foreach ($ws in $wss) {
    $k = Get-ProjDir $ws
    if (-not $groups.ContainsKey($k)) { $groups[$k] = @() }
    $groups[$k] += (Get-WsName $ws)
}
foreach ($k in $groups.Keys) {
    if ($groups[$k].Count -gt 1) {
        Warn ("대화 폴더를 공유한다: " + ($groups[$k] -join ' ') + "  → 대화는 cwd 로 갈라내지만, 필요하면 상태\고정세션.txt 로 못박을 것")
    }
}

# 편집기 설정 점검 (고치지는 않는다 — 설치 프로그램이 한 번 켠다)
$s = Join-Path $env:APPDATA 'Code\User\settings.json'
if (-not ((Test-Path -LiteralPath $s) -and ((Get-Content -LiteralPath $s -Raw -Encoding UTF8) -match '"task\.allowAutomaticTasks"\s*:\s*"on"'))) {
    Warn '편집기 설정에 "task.allowAutomaticTasks": "on" 이 없다 — 폴더를 열어도 자동 작업이 안 돈다'
}
Say "===== 끝 ====="
