# -----------------------------------------------------------------------------
# 회선 감시 (윈도우, 작업 스케줄러가 로그인 때 띄워 계속 돌린다)
#   끊겼다 돌아오면 resume-all.ps1 을 부른다. 짧게 출렁인 것은 무시한다.
# -----------------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'common.ps1')

$log = Join-Path $STATE '회선로그.jsonl'
function NLog {
    param([string]$Event, [string]$Note = '')
    $o = '{{"ts":"{0}","event":"{1}","note":"{2}"}}' -f (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'), $Event, $Note
    Add-Content -LiteralPath $log -Value $o -Encoding UTF8
}

NLog 'start' "감시 시작 ($NET_POLL 초 간격)"
$downSince = $null
while ($true) {
    if (Test-Online) {
        if ($downSince) {
            $dur = [int]((Get-Date) - $downSince).TotalSeconds
            $downSince = $null
            NLog 'up' "$dur 초 끊겼다 돌아옴"
            if ($dur -ge $NET_DOWN_MIN) {
                & (Join-Path $PSScriptRoot 'resume-all.ps1') -Why "회선 복구($dur 초)" -NoWait `
                    *>> (Join-Path $STATE 'resume-all.log')
            }
        }
    } else {
        if (-not $downSince) { $downSince = Get-Date; NLog 'down' '끊김' }
    }
    Start-Sleep -Seconds $NET_POLL
}
