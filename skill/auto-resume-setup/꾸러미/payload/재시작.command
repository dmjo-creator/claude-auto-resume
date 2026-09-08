#!/bin/bash
# 손으로 전체 재시작 (맥) — 더블클릭. 편집기를 정상 종료하고 모든 워크스페이스를 되살린다.
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
echo "===== $(now) 손으로 재시작 ====="
if pgrep -f "Visual Studio Code.app/Contents/MacOS/Code" >/dev/null 2>&1; then
    echo "  편집기를 닫는다"
    osascript -e 'tell application "Visual Studio Code" to quit' >/dev/null 2>&1
    for _ in $(seq 1 20); do sleep 1; pgrep -f "Visual Studio Code.app/Contents/MacOS/Code" >/dev/null 2>&1 || break; done
    pgrep -f "Visual Studio Code.app/Contents/MacOS/Code" >/dev/null 2>&1 && { pkill -f "Visual Studio Code.app/Contents/MacOS/Code"; sleep 3; }
fi
rm -f "$STATE/.마지막전체재개"       # 방금 돌았어도 이번엔 사람이 시킨 것이다
bash "$CFG/resume_all.sh" --why "손으로 재시작" --no-wait
echo; echo "  안 뜬 창이 있으면 그 창 터미널에서:  claude --continue"
echo "  (이 창은 닫아도 된다)"
