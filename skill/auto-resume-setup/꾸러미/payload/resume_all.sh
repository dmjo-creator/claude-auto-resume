#!/bin/bash
# -----------------------------------------------------------------------------
# 전체 재개 (맥) — 맥이 켜졌거나 회선이 돌아왔거나 사람이 재시작할 때
#
#     bash 재시작설정/resume_all.sh [--why 사유] [--only 폴더명] [--no-wait]
#
# 하는 일
#   0) sync.sh — 새로 만든 폴더에도 발판을 심는다
#   1) 회선을 기다린다 (부팅 직후엔 아직 없다)
#   2) (상태/서비스.txt 에 적어 두었다면) 그 워크스페이스의 launchd 서비스를 깨운다
#   3) claude 가 죽어 있는 워크스페이스마다: 표식 → 편집기로 폴더 열기(간격을 둔다)
#   4) 정해진 시간 안에 안 뜨면 터미널로 직접 띄운다
#
# ★ 발행·전송·배포는 여기서 일어나지 않는다. 창과 claude 만 되살린다.
# ★ 살아 있는 claude 는 건드리지 않는다.
# -----------------------------------------------------------------------------
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WHY="자동 재개"; ONLY=""; WAIT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --why)  WHY="${2:-}"; shift 2 ;;
        --only) ONLY="${2:-}"; shift 2 ;;
        --no-wait) WAIT=0; shift ;;
        *) shift ;;
    esac
done
echo "===== $(now) 전체 재개 ($WHY) ====="
jlog start all "$WHY${ONLY:+ · only $ONLY}"

# 짧은 시간 안에 두 번 돌지 않는다 (부팅 직후 재개와 회선 복구가 겹친다)
LASTF="$STATE/.마지막전체재개"; LAST="$(cat "$LASTF" 2>/dev/null || echo 0)"
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
if [ -z "$ONLY" ] && [ $(( $(date +%s) - LAST )) -lt "$RESUME_GAP" ]; then
    echo "  ${RESUME_GAP}초 안에 이미 돌았다 — 건너뛴다"; jlog skipped all "gap"; exit 0
fi
date +%s > "$LASTF"

bash "$CFG/sync.sh" --quiet

if [ "$WAIT" = 1 ]; then
    if wait_online "$NET_WAIT"; then echo "  회선 정상"
    else echo "  [!] ${NET_WAIT}초 안에 회선이 안 돌아왔다 — 그래도 진행한다"; jlog net all "대기 실패"; fi
fi

UID_N="$(id -u)"
TARGETS=()
while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    n="$(ws_name "$ws")"
    [ -z "$ONLY" ] || [ "$n" = "$ONLY" ] || continue
    for l in $(services_for "$n"); do
        launchctl kickstart "gui/$UID_N/$l" >/dev/null 2>&1 && echo "  깨움: $l"
    done
    if [ -f "$STATE/.전체끔" ] || [ -f "$STATE/$n.끔" ]; then echo "  $n: 꺼 둠"; continue; fi
    if claude_alive "$ws"; then echo "  $n: claude 살아 있음 (pid $CLAUDE_PID) — 그대로 둔다"; continue; fi
    TARGETS+=("$ws")
done < <(list_workspaces)

[ "${#TARGETS[@]}" -gt 0 ] || { echo "  되살릴 것이 없다"; jlog done all "nothing"; exit 0; }

VSCODE="/Applications/Visual Studio Code.app"
if [ -d "$VSCODE" ]; then
    for ws in "${TARGETS[@]}"; do
        n="$(ws_name "$ws")"
        printf '%s · %s' "$(now)" "$WHY" > "$STATE/$n.표식"
        echo "  편집기로 연다: $n"
        open -a "$VSCODE" "$ws"
        sleep "$OPEN_STAGGER"
    done
    echo "  자동 작업을 ${FOLDEROPEN_WAIT}초 기다린다"
    for _ in $(seq 1 $((FOLDEROPEN_WAIT/2))); do
        sleep 2; all=1
        for ws in "${TARGETS[@]}"; do claude_alive "$ws" || all=0; done
        [ "$all" = 1 ] && break
    done
else
    echo "  [!] VS Code 를 못 찾았다 — 터미널로 띄운다"
fi

for ws in "${TARGETS[@]}"; do
    n="$(ws_name "$ws")"
    if claude_alive "$ws"; then echo "  $n: 편집기 안에서 떴다 (pid $CLAUDE_PID)"; jlog done "$n" "vscode"; continue; fi
    echo "  $n: 안 떴다 — 터미널로 직접 띄운다"
    jlog fallback "$n" "terminal"
    osascript -e "tell application \"Terminal\" to do script \"bash '$CFG/resume_claude.sh' '$ws'\"" >/dev/null 2>&1
    sleep 2
done
echo "===== 끝 ====="
