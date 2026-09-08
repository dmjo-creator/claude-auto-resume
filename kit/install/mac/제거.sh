#!/bin/bash
# 제거 (맥) — 자동실행 등록만 지운다. 워크스페이스 파일과 대화는 건드리지 않는다.
#   bash install/mac/제거.sh [--전부]      --전부 를 주면 발판·규칙 블록·재시작설정 폴더까지 지운다
set -u
UID_N="$(id -u)"; LA="$HOME/Library/LaunchAgents"
ALL=0; [ "${1:-}" = "--전부" ] && ALL=1
echo "===== 클로드코드 자동재개 제거 ====="
for l in kr.claudecode.resume kr.claudecode.netwatch; do
    launchctl bootout "gui/$UID_N/$l" >/dev/null 2>&1
    rm -f "$LA/$l.plist" && echo "  자동실행 해제: $l"
done
if [ "$ALL" = 1 ]; then
    ROOT="${2:-$HOME/클로드코드}"; CFG="$ROOT/재시작설정"
    if [ -d "$CFG" ]; then
        # 각 폴더의 발판과 규칙 블록을 걷어낸다
        # 루트 바로 아래 폴더 + 묶음 폴더(_bundle 등) 안의 하위 폴더까지 훑는다
        for d in "$ROOT"/*/ "$ROOT"/*/*/; do
            [ -d "$d" ] || continue
            f="$d/.vscode/tasks.json"
            [ -f "$f" ] && grep -q "재시작설정이 만든 파일" "$f" && rm -f "$f" && echo "  발판 제거: $(basename "$d")"
            c="$d/CLAUDE.md"
            if [ -f "$c" ] && grep -q "재시작설정 관리 블록 시작" "$c"; then
                python3 - "$c" <<'PY'
import sys,pathlib
p=pathlib.Path(sys.argv[1]); out=[]; skip=False
for l in p.read_text(encoding="utf-8").split("\n"):
    if l.startswith("<!-- 재시작설정 관리 블록 시작"): skip=True; continue
    if l.startswith("<!-- 재시작설정 관리 블록 끝"): skip=False; continue
    if not skip: out.append(l)
p.write_text("\n".join(out), encoding="utf-8")
PY
                echo "  규칙 블록 제거: $(basename "$d")"
            fi
        done
        echo "  재시작설정 폴더는 남겨 둔다 (로그·설정이 들어 있다): $CFG"
        echo "  정말 지우려면:  rm -rf \"$CFG\""
    fi
fi
echo "  대화 이력(~/.claude)과 작업 파일은 건드리지 않았다."
echo "===== 끝 ====="
