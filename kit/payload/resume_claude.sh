#!/bin/bash
# -----------------------------------------------------------------------------
# claude 를 실제로 띄우는 곳 (맥) — **여기 하나뿐이다**
#
#     bash 재시작설정/resume_claude.sh <워크스페이스 절대경로>
#
# 부르는 쪽
#   ① 각 폴더의 .vscode/tasks.json (폴더를 열 때)  ← sync.sh 가 심어 둔 발판
#   ② resume_all.sh 의 대비책 (①이 안 뜨면 터미널로)
#
# 규칙
#   · 폴더를 열면 **항상** 띄운다. 끄려면 상태/<폴더명>.끔 또는 상태/.전체끔
#   · 이미 살아 있으면 새로 띄우지 않는다 — 시각이 아니라 프로세스를 본다
#   · 대화는 "가장 최근" 이 아니라 "그 폴더의 것 중 가장 최근" 을 --resume 한다
#   · claude 는 **워크스페이스 폴더에서** 띄운다 — 대화 이력이 폴더별이라
#     하위 폴더로 들어가면 조용히 새 대화가 시작된다
#
# 권한 (2026-09-08)
#   자동재개는 사람이 안 보는 사이에 뜬다. 권한을 물으면 아무도 답하지 않아
#   claude 가 도구를 하나도 못 쓴 채 멈춘다. 그래서 묻지 않고 실행하도록 띄운다.
#   (묻게 하고 싶으면 아래 exec 줄에서 --dangerously-skip-permissions 를 지운다.)
# -----------------------------------------------------------------------------
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WS="${1:-}"
[ -n "$WS" ] && [ -d "$WS" ] || { echo "[!] 워크스페이스 경로가 필요하다: $0 <폴더>"; exit 1; }
WS="$(norm_path "$WS")"; NAME="$(ws_name "$WS")"
MARK="$STATE/$NAME.표식"

jlog called "$NAME" "resume_claude 가 불렸다"

if [ -f "$STATE/.전체끔" ] || [ -f "$STATE/$NAME.끔" ]; then
    echo "(자동 실행이 꺼져 있다 — 재시작설정/상태/ 의 .전체끔 또는 $NAME.끔 을 지우면 켜진다)"
    jlog off "$NAME" "꺼 둠"; exit 0
fi

# 같은 폴더를 거의 동시에 두 번 띄우지 않게 잠근다 (folderOpen 과 Reload 가 겹칠 때, 11-12)
#   exec 뒤에는 풀 수 없어서 시간으로 푼다 — LOCK_SEC 초가 지난 잠금은 낡은 것으로 보고 가져온다.
LOCK="$STATE/$NAME.띄우는중"; LOCK_SEC=30
if ! mkdir "$LOCK" 2>/dev/null; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$LOCK_SEC" ]; then
        echo "(다른 쪽이 ${age}초 전에 이 폴더의 claude 를 띄우기 시작했다 — 겹치지 않게 그만둔다)"
        jlog skipped "$NAME" "띄우는 중(잠금 ${age}초)"; exit 0
    fi
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || { jlog skipped "$NAME" "잠금 못 잡음"; exit 0; }
fi

claude_alive "$WS"; rc=$?
if [ "$rc" = 0 ]; then
    echo "(claude 가 이미 떠 있다 — pid $CLAUDE_PID. 새로 띄우지 않는다)"
    jlog skipped "$NAME" "이미 실행 중 pid $CLAUDE_PID"; exit 0
fi
if [ "$rc" = 2 ]; then
    echo "[!] 프로세스 목록을 볼 수 없어 claude 가 이미 떠 있는지 모른다 — 겹치지 않게 띄우지 않는다. 직접: claude --continue"
    jlog skipped "$NAME" "생사 판정 불가"; exit 0
fi

if [ -f "$MARK" ]; then WHY="$(cat "$MARK")"; rm -f "$MARK"; else WHY="폴더를 열었다"; fi

if ! command -v claude >/dev/null 2>&1; then
    echo "[!] claude 를 찾지 못했다. 이 창에서 직접:  claude --continue"
    echo "    (설치: https://claude.ai/download 또는  npm i -g @anthropic-ai/claude-code)"
    jlog fail "$NAME" "claude 없음"; exit 0
fi

# exec 로 넘기므로 이 셸의 PID 가 곧 claude 의 PID 다
echo "$$" > "$STATE/$NAME.pid"

PROMPT_FILE="$PROMPTS/$NAME.txt"; [ -f "$PROMPT_FILE" ] || PROMPT_FILE="$PROMPTS/_기본.txt"
PROMPT="$(cat "$PROMPT_FILE" 2>/dev/null)"

read -r MODE SID <<<"$(pick_session "$WS")"
echo "===== 작업 자동 재개 · $NAME ($WHY) ====="
echo "  폴더: $WS"
cd "$WS" || exit 1
case "$MODE" in
    resume) echo "  대화: $SID (이어받기)"; jlog resume "$NAME" "$WHY · resume ${SID:0:8}"
            exec claude --dangerously-skip-permissions --resume "$SID" "$PROMPT" ;;
    *)      echo "  대화: 이력 없음 — 새로 시작";  jlog resume "$NAME" "$WHY · new"
            exec claude --dangerously-skip-permissions "$PROMPT" ;;
esac
