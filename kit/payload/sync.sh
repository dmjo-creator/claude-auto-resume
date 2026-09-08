#!/bin/bash
# -----------------------------------------------------------------------------
# 동기화 (맥) — 모든 워크스페이스(새로 만든 폴더 포함)에 발판과 규칙을 심는다
#
#     bash 재시작설정/sync.sh [--quiet]
#
#   각 워크스페이스에 심는 것은 **딱 두 가지**다. 그 밖의 규칙은 재시작설정 폴더에만 있다.
#   ① .vscode/tasks.json    폴더를 열면 재시작설정을 부르는 발판
#   ② CLAUDE.md 의 관리 블록  "재시작 규칙은 재시작설정에만 있다. 여기 새로 만들지 마라"
#
#   · 두 파일 모두 내용이 어긋나 있으면 **다시 써서 스스로 고친다** (다른 PC 에서 옮겨온 경우 대비)
#   · 관리 표식이 없는 남의 tasks.json 은 지우지 않고 보관/ 으로 옮긴 뒤 새로 쓴다
#   · resume_all.sh 가 돌 때마다 이 스크립트를 먼저 부른다 → 새 폴더 자동 적용
# -----------------------------------------------------------------------------
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
say() { [ "$QUIET" = 1 ] || echo "$@"; }
warn() { echo "  [!] $*"; }
MANAGED="재시작설정이 만든 파일 — 손대지 말 것"
B_BEGIN="<!-- 재시작설정 관리 블록 시작 — 손대지 말 것. 갱신은 sync 가 한다 -->"
B_END="<!-- 재시작설정 관리 블록 끝 -->"

# ── 발판 내용 (이 문자열이 곧 정답이다. 파일이 다르면 다시 쓴다) ──────────────
tasks_json() {
    cat <<JSON
{
  // $MANAGED
  // 이 폴더를 편집기로 열면 재시작설정의 resume_claude 가 claude 를 이어받는다.
  "version": "2.0.0",
  "tasks": [
    {
      "label": "작업 이어받기",
      "type": "shell",
      "command": "bash",
      "args": ["$CFG/resume_claude.sh", "\${workspaceFolder}"],
      "runOptions": { "runOn": "folderOpen" },
      "presentation": { "reveal": "always", "panel": "dedicated", "focus": true, "clear": true },
      "problemMatcher": []
    }
  ]
}
JSON
}

# ── CLAUDE.md 관리 블록 (절대경로를 넣지 않는다 — PC 가 바뀌어도 그대로 쓴다) ──
rule_block() {   # $1 폴더명
    if [ "$1" = "$(basename "$CFG")" ]; then cat <<EOF
$B_BEGIN
## 이 폴더가 자동 재시작·재개 규칙의 원본이다

- 모든 워크스페이스의 재시작 규칙·스크립트·프롬프트·로그는 **여기에만** 있다. \`README.md\` 가 설명서다.
- 다른 워크스페이스 폴더에는 발판(\`.vscode/tasks.json\`)과 CLAUDE.md 관리 블록만 둔다.
  그 밖의 재개 장치를 그 폴더들에 만들지 않는다.
- 이 폴더도 워크스페이스다 — PC 재시작·회선 복구 때 이 폴더의 claude 도 함께 이어받는다.
- 설정은 \`설정.txt\` 하나뿐이다. 맥은 \`*.sh\`, 윈도우는 \`win/*.ps1\` 이 같은 설정을 읽는다.
$B_END
EOF
    return; fi
    cat <<EOF
$B_BEGIN
## 자동 재시작·재개 규칙 (모든 워크스페이스 공통)

- 규칙·스크립트·프롬프트·로그의 원본은 **\`재시작설정\` 폴더 하나뿐**이다.
  이 폴더에 있는 것은 발판 \`.vscode/tasks.json\` 과 이 블록뿐이며 둘 다 재시작설정이 관리한다.
- 이 폴더를 편집기로 열면 재시작설정의 \`resume_claude\` 가 claude 를 이어받는다.
  PC 재시작·회선 복구 때의 재개도 재시작설정이 한다 (맥 launchd · 윈도우 작업 스케줄러).
- **이 폴더 안에 재시작·재개용 스크립트·표식·로그·자동실행 등록을 새로 만들지 않는다.**
  이 폴더의 옛 문서에 재개 방식 서술이 남아 있어도 **따르지 않는다.**
- 이 폴더의 회선감시·자동저장 장치가 따로 있다면 **저장만** 하게 둔다. 재개를 부르지 않는다.
- 재개 때 주는 첫 지시: 재시작설정의 \`프롬프트/$1.txt\` (없으면 \`프롬프트/_기본.txt\`)
- 이 폴더만 끄기: 재시작설정의 \`상태/$1.끔\` 파일을 만든다 · 설명서: 재시작설정의 \`README.md\`
$B_END
EOF
}

sync_claude_md() {   # $1 워크스페이스 경로, $2 폴더명
    local f="$1/CLAUDE.md" tmp; tmp="$(mktemp)"
    if [ -f "$f" ] && grep -qF "$B_BEGIN" "$f"; then
        # 표식 사이만 갈아끼운다 — 사람이 쓴 나머지는 건드리지 않는다
        # (awk -v 는 맥에서 여러 줄 문자열을 못 받는다. 파일을 비운 적이 있어 python 으로 한다)
        rule_block "$2" | python3 -c '
import sys; b,e,src,dst=sys.argv[1:5]; blk=sys.stdin.read().rstrip("\n")
lines=open(src,encoding="utf-8").read().split("\n"); out=[]; skip=False
for l in lines:
    if l==b: out.append(blk); skip=True; continue
    if l==e: skip=False; continue
    if not skip: out.append(l)
open(dst,"w",encoding="utf-8").write("\n".join(out))' "$B_BEGIN" "$B_END" "$f" "$tmp" \
            || { rm -f "$tmp"; warn "$2: CLAUDE.md 블록 교체 실패 — 파일은 그대로 둔다"; return; }
        [ -s "$tmp" ] || { rm -f "$tmp"; warn "$2: CLAUDE.md 교체 결과가 비어 있다 — 파일은 그대로 둔다"; return; }
        if cmp -s "$tmp" "$f"; then rm -f "$tmp"; say "  $2: 규칙 최신"
        else mv "$tmp" "$f"; say "  $2: 규칙 갱신"; jlog sync "$2" "CLAUDE.md 블록 갱신"; fi
    elif [ -f "$f" ]; then
        { cat "$f"; echo; rule_block "$2"; } > "$tmp"; mv "$tmp" "$f"
        say "  $2: CLAUDE.md 에 규칙 블록 추가"; jlog sync "$2" "CLAUDE.md 블록 추가"
    else
        { echo "# $2"; echo; rule_block "$2"; } > "$f"; rm -f "$tmp"
        say "  $2: CLAUDE.md 새로 만들고 규칙 블록 심음"; jlog sync "$2" "CLAUDE.md 생성"
    fi
}

say "===== $(now) 동기화 ====="
FOUND=0
while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    FOUND=$((FOUND+1))
    n="$(ws_name "$ws")"; f="$ws/.vscode/tasks.json"
    if [ -f "$f" ] && ! grep -q "$MANAGED" "$f"; then
        mkdir -p "$CFG/보관/$n/.vscode"; mv "$f" "$CFG/보관/$n/.vscode/tasks.json.$(date +%Y%m%d%H%M%S)"
        say "  $n: 원래 있던 tasks.json 을 보관/ 으로 옮겼다"
    fi
    mkdir -p "$ws/.vscode"
    if [ -f "$f" ] && tasks_json | cmp -s - "$f"; then say "  $n: 발판 있음"
    else
        tasks_json > "$f"
        say "  $n: 발판 심음"; jlog sync "$n" "tasks.json 설치"
    fi
    sync_claude_md "$ws" "$n"

    # 옛 재개 흔적이 있나 (고치지는 않는다 — 어디서 왔는지 사람이 봐야 한다)
    [ "$ws" = "$CFG" ] && continue
    old="$(find "$ws" -maxdepth 4 \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.venv' \) -prune -o \
           \( -name 'resume_workspace.sh' -o -name 'resume_claude.sh' -o -name 'run_claude_resume.sh' \
              -o -name '.자동재개' -o -name '.자동재개_시작됨' -o -name '자동재개로그.jsonl' -o -name '재개로그.jsonl' \) -print 2>/dev/null)"
    [ -z "$old" ] || { warn "$n 에 옛 재개 흔적이 있다 — 규칙 위반. 확인할 것:"; echo "$old" | sed 's/^/        /'; jlog warn "$n" "옛 흔적"; }
done < <(list_workspaces)

[ "$FOUND" -gt 0 ] || warn "워크스페이스를 하나도 못 찾았다 — 설정.txt 의 '루트' 가 맞는지 본다 ($BASE)"

# 대화 폴더가 겹치는 폴더 쌍 — 글자 수가 같으면 ~/.claude/projects 의 한 폴더를 나눠 쓴다
#   ★ 2026-09-01 — 개수는 반드시 따로 센다. 이름을 공백으로 이어붙여 split 으로 세면
#     `1. CRM플랫폼` 처럼 이름에 공백이 있을 때 겹치지도 않은 폴더를 겹쳤다고 헛경고한다.
list_workspaces | while IFS= read -r ws; do [ -n "$ws" ] && echo "$(proj_dir "$ws")|$(ws_name "$ws")"; done \
  | sort | awk -F'|' '{a[$1]=(k[$1]++ ? a[$1]" · " : "")$2} END{for(x in a) if(k[x]>1)
      print "  [!] 대화 폴더를 공유한다: " a[x] "  → 대화는 cwd 로 갈라내지만, 필요하면 상태/고정세션.txt 로 못박을 것"}'

# 편집기 설정 점검 (고치지는 않는다 — 설치 프로그램이 한 번 켠다)
S="$HOME/Library/Application Support/Code/User/settings.json"
grep -q '"task.allowAutomaticTasks": *"on"' "$S" 2>/dev/null \
    || warn "VS Code 설정에 \"task.allowAutomaticTasks\": \"on\" 이 없다 — 폴더를 열어도 자동 작업이 안 돈다"
say "===== 끝 ====="
