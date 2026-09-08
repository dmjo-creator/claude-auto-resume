#!/bin/bash
# 회선 감시 (맥, launchd KeepAlive) — 끊겼다 돌아오면 resume_all.sh 를 부른다
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
LOG="$STATE/회선로그.jsonl"
nlog() { printf '{"ts":"%s","event":"%s","note":"%s"}\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "${2:-}" >> "$LOG"; }
nlog start "감시 시작 (${NET_POLL}초 간격)"
down_since=0
while :; do
    if online; then
        if [ "$down_since" -gt 0 ]; then
            dur=$(( $(date +%s) - down_since )); down_since=0
            nlog up "${dur}초 끊겼다 돌아옴"
            if [ "$dur" -ge "$NET_DOWN_MIN" ]; then
                bash "$CFG/resume_all.sh" --why "회선 복구(${dur}초)" --no-wait >> "$STATE/resume_all.log" 2>&1
            fi
        fi
    else
        [ "$down_since" -gt 0 ] || { down_since=$(date +%s); nlog down "끊김"; }
    fi
    sleep "$NET_POLL"
done
