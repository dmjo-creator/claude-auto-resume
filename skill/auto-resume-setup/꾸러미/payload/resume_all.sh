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

step "발판 심기 (sync)"
bash "$CFG/sync.sh" --quiet

if [ "$WAIT" = 1 ]; then
    step "회선 확인"
    if wait_online "$NET_WAIT"; then echo "  회선 정상"
    else echo "  [!] ${NET_WAIT}초 안에 회선이 안 돌아왔다 — 그래도 진행한다"; jlog net all "대기 실패"; fi
fi

UID_N="$(id -u)"
TARGETS=()
step "서비스 깨우기 · 생사 판정"
alive_snapshot   # 모든 폴더 판정을 사진 한 장으로
while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    n="$(ws_name "$ws")"
    [ -z "$ONLY" ] || [ "$n" = "$ONLY" ] || continue
    for l in $(services_for "$n"); do
        r="$(wake_service "$l")"
        case "$r" in
            gui|system) echo "  깨움($r): $l" ;;
            fail:*)     echo "  [!] 못 깨움: $l — ${r#fail:}"; jlog svcfail "$n" "$l: ${r#fail:}" ;;
        esac
    done
    if [ -f "$STATE/.전체끔" ] || [ -f "$STATE/$n.끔" ]; then echo "  $n: 꺼 둠"; continue; fi
    claude_alive "$ws"; rc=$?
    if [ "$rc" = 0 ]; then echo "  $n: claude 살아 있음 (pid $CLAUDE_PID) — 그대로 둔다"; continue; fi
    if [ "$rc" = 2 ]; then echo "  [!] $n: 프로세스 목록을 못 봐 생사 판정 불가 — 겹쳐 띄우지 않게 건너뛴다"; jlog skipped "$n" "생사 판정 불가"; continue; fi
    TARGETS+=("$ws")
done < <(list_workspaces)
alive_forget

[ "${#TARGETS[@]}" -gt 0 ] || { echo "  되살릴 것이 없다"; jlog done all "nothing"; exit 0; }

VSCODE="/Applications/Visual Studio Code.app"
if [ -d "$VSCODE" ]; then
    step "편집기로 창 열기 (${#TARGETS[@]}곳)"
    OPEN_AT=(); OPEN_TS=(); RELOADED=()
    for i in "${!TARGETS[@]}"; do
        ws="${TARGETS[$i]}"; n="$(ws_name "$ws")"
        printf '%s · %s' "$(now)" "$WHY" > "$STATE/$n.표식"
        echo "  편집기로 연다: $n"
        OPEN_AT[$i]="$(date +%s)"; OPEN_TS[$i]="$(date '+%Y-%m-%dT%H:%M:%S')"; RELOADED[$i]=0
        open -a "$VSCODE" "$ws"
        sleep "$OPEN_STAGGER"
    done
    # ★ 창이 이미 열려 있던 폴더는 folderOpen 이 다시 돌지 않는다 → 45초를 다 기다려 봐야 헛일이었다 (11-12 시험).
    #   folderOpen 이 돌면 몇 초 안에 기록에 called 가 남는다 (10-28 부팅 때 7초).
    #   그래서 창을 연 뒤 CALLED_WAIT 초 안에 called 가 없으면 기다리지 않고 바로 Reload 한다.
    step "folderOpen 작업을 최대 ${FOLDEROPEN_WAIT}초 기다린다 (${CALLED_WAIT:-15}초 안에 안 불리면 바로 Reload)"
    T0="$(date +%s)"
    while [ $(( $(date +%s) - T0 )) -lt "$FOLDEROPEN_WAIT" ]; do
        sleep 2; all=1; todo=()
        alive_snapshot
        for i in "${!TARGETS[@]}"; do
            claude_alive "${TARGETS[$i]}" && continue
            all=0
            [ "${VSCODE_AUTO_RELOAD:-0}" = 1 ] && [ "${RELOADED[$i]}" = 0 ] || continue
            [ $(( $(date +%s) - OPEN_AT[i] )) -ge "${CALLED_WAIT:-15}" ] || continue
            was_called "$(ws_name "${TARGETS[$i]}")" "${OPEN_TS[$i]}" || todo+=("$i")
        done
        alive_forget
        [ "$all" = 1 ] && break
        for i in ${todo[@]+"${todo[@]}"}; do
            ws="${TARGETS[$i]}"; n="$(ws_name "$ws")"; RELOADED[$i]=1
            echo "  $n: ${CALLED_WAIT:-15}초 안에 folderOpen 이 안 불렸다 (창이 이미 열려 있었다) — 바로 Reload 한다"
            jlog reload "$n" "folderOpen 미발동 — 바로 Reload"
            vscode_reload "$ws" || { echo "  [!] $n: 키 입력을 멈췄다 (${VSCODE_RELOAD_WHY}) — 끝에 터미널로 띄운다"; jlog reloadskip "$n" "$VSCODE_RELOAD_WHY"; }
        done
    done
    # 그래도 안 뜬 폴더 (folderOpen 은 불렸는데 claude 가 없다 등) — 아직 Reload 안 한 곳만 한 번 더
    if [ "${VSCODE_AUTO_RELOAD:-0}" = 1 ]; then
        again=0
        alive_snapshot
        for i in "${!TARGETS[@]}"; do
            ws="${TARGETS[$i]}"; claude_alive "$ws" && continue
            [ "${RELOADED[$i]}" = 0 ] || continue
            n="$(ws_name "$ws")"; echo "  $n: 창은 열려 있는데 claude 가 없다 — 편집기 창을 Reload 한다"
            jlog reload "$n" "folderOpen 재실행 유도"; RELOADED[$i]=1; again=1
            vscode_reload "$ws" || { echo "  [!] $n: 키 입력을 멈췄다 (${VSCODE_RELOAD_WHY}) — 끝에 터미널로 띄운다"; jlog reloadskip "$n" "$VSCODE_RELOAD_WHY"; }
        done
        alive_forget
        [ "$again" = 1 ] && for _ in $(seq 1 $((FOLDEROPEN_WAIT/3))); do
            sleep 2; all=1
            alive_snapshot; for ws in "${TARGETS[@]}"; do claude_alive "$ws" || all=0; done; alive_forget
            [ "$all" = 1 ] && break
        done
    fi
else
    echo "  [!] VS Code 를 못 찾았다 — 터미널로 띄운다"
fi

step "마지막 판정"
alive_snapshot   # 마지막 판정도 한 장으로
for ws in "${TARGETS[@]}"; do
    n="$(ws_name "$ws")"
    if claude_alive "$ws"; then echo "  $n: 편집기 안에서 떴다 (pid $CLAUDE_PID)"; jlog done "$n" "vscode"; continue; fi
    echo "  $n: 안 떴다 — 터미널로 직접 띄운다"
    jlog fallback "$n" "terminal"
    osascript -e "tell application \"Terminal\" to do script \"bash '$CFG/resume_claude.sh' '$ws'\"" >/dev/null 2>&1
    sleep 2
done
alive_forget
echo "===== 끝 ====="
