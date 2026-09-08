#!/bin/bash
# -----------------------------------------------------------------------------
# 공용 함수 (맥) — 모든 맥 스크립트가 이 파일을 읽는다. 설정은 설정.txt 하나뿐이다.
# -----------------------------------------------------------------------------
CFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$CFG/상태"
PROMPTS="$CFG/프롬프트"
mkdir -p "$STATE" "$PROMPTS"

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH";; esac
case ":$PATH:" in *":/opt/homebrew/bin:"*) ;; *) PATH="/opt/homebrew/bin:$PATH";; esac
case ":$PATH:" in *":/usr/local/bin:"*) ;; *) PATH="/usr/local/bin:$PATH";; esac
export PATH LANG="${LANG:-ko_KR.UTF-8}"

# ── 설정 읽기 ────────────────────────────────────────────────────────────────
#   bash 는 한글 **변수명**을 못 쓴다. 그래서 한글 이름을 영문 변수로 옮겨 담는다.
BASE=""; EXCLUDE="data"; CONTAINERS="_bundle"; EXTRA_WORKSPACES=""
NET_WAIT=300; OPEN_STAGGER=4; FOLDEROPEN_WAIT=30; RESUME_GAP=120
NET_DOWN_MIN=30; NET_POLL=20; MIN_SESSION_BYTES=20000
load_config() {
    local f="$CFG/설정.txt" line k v
    [ -f "$f" ] || { echo "[!] 설정 파일이 없다: $f" >&2; return 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"                       # 윈도우에서 고친 파일 대비 (줄끝 CR)
        line="${line#$'\xef\xbb\xbf'}"                # 윈도우 PowerShell 이 남기는 BOM
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in *=*) ;; *) continue ;; esac
        k="${line%%=*}"; v="${line#*=}"
        k="$(printf '%s' "$k" | tr -d ' \t')"
        v="$(printf '%s' "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        case "$k" in
            루트)            BASE="$v" ;;
            제외)            EXCLUDE="$v" ;;
            컨테이너)         CONTAINERS="$v" ;;
            추가워크스페이스)   EXTRA_WORKSPACES="$v" ;;
            회선대기)         NET_WAIT="$v" ;;
            창간격)          OPEN_STAGGER="$v" ;;
            발판대기)         FOLDEROPEN_WAIT="$v" ;;
            재개간격)         RESUME_GAP="$v" ;;
            끊김최소)         NET_DOWN_MIN="$v" ;;
            확인간격)         NET_POLL="$v" ;;
            최소대화크기)      MIN_SESSION_BYTES="$v" ;;
        esac
    done < "$f"
    [ -n "$BASE" ] || { echo "[!] 설정.txt 의 '루트' 가 비어 있다" >&2; return 1; }
    return 0
}
load_config || exit 1

now() { date '+%Y-%m-%d %H:%M:%S'; }

# 기록 — 상태/재시작로그.jsonl   (event, ws, note)
jlog() {
    printf '{"ts":"%s","event":"%s","ws":"%s","note":"%s"}\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "${2:-}" "${3:-}" >> "$STATE/재시작로그.jsonl"
}

# 경로를 NFC 로 맞춘다 — **여기를 거치지 않은 경로를 쓰지 말 것**
#   맥 파일이름에는 NFD(자모 분리)로 저장된 것이 섞여 있다. glob 이 주는 이름은 그 원본이라
#   같은 폴더인데도 글자가 달라지고, 그러면 대화 폴더 이름이 어긋나 이어받기가 조용히
#   "새 대화" 로 떨어진다. cd+pwd 로는 정규화되지 않는다 — 셸은 준 글자를 그대로 돌려준다.
norm_path() {
    python3 -c 'import sys,unicodedata; sys.stdout.write(unicodedata.normalize("NFC", sys.argv[1]))' "$1" 2>/dev/null \
        || printf '%s' "$1"
    echo
}

# 워크스페이스 목록 (절대경로 NFC, 한 줄에 하나)
list_workspaces() {
    local d n skip x c s
    for d in "$BASE"/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"; n="$(basename "$d")"
        case "$n" in .*) continue ;; esac
        skip=0
        for x in $EXCLUDE; do [ "$n" = "$x" ] && skip=1; done
        for c in $CONTAINERS; do
            if [ "$n" = "$c" ]; then
                skip=1
                for s in "$d"/*/; do
                    [ -d "$s" ] || continue
                    s="${s%/}"; case "$(basename "$s")" in .*) continue ;; esac
                    norm_path "$s"
                done
            fi
        done
        [ "$skip" = 1 ] || norm_path "$d"
    done
    for e in $EXTRA_WORKSPACES; do [ -d "$e" ] && norm_path "$e"; done
}

ws_name() { basename "$1"; }

# claude 가 대화를 보관하는 폴더 (~/.claude/projects/<경로의 비영숫자→'-'>)
proj_dir() { echo "$HOME/.claude/projects/$(printf '%s' "$(norm_path "$1")" | sed 's/[^A-Za-z0-9]/-/g')"; }

# 이어받을 대화 고르기 → "resume <ID>" | "new"
#
#   ★ 대화 폴더 이름은 경로의 비영숫자를 전부 '-' 로 바꾼 것이라 **글자 수만 같으면 겹친다.**
#     (예: 통합플랫폼 과 재시작설정 → 같은 폴더). 그래서 파일 시각만 보면 남의 폴더 대화를 문다.
#     대화 파일 안의 cwd 를 워크스페이스와 대조해서 고른다. 비교는 문자열이 아니라 inode 로 한다.
#   ★ 못 고르면 --continue 가 아니라 새 대화로 간다. --continue 는 남의 폴더 대화를 물 수 있다.
pick_session() {
    local ws="$1" name pin pd f
    name="$(ws_name "$ws")"
    pin="$(awk -v n="$name" '$1==n{print $2}' "$STATE/고정세션.txt" 2>/dev/null | tail -1)"
    pd="$(proj_dir "$ws")"
    if [ -n "$pin" ] && [ -f "$pd/$pin.jsonl" ]; then echo "resume $pin"; return; fi
    [ -d "$pd" ] || { echo "new"; return; }
    f="$(WS="$ws" PD="$pd" MINB="$MIN_SESSION_BYTES" python3 -c '
import os, sys, json, glob
ws, pd, minb = os.environ["WS"], os.environ["PD"], int(os.environ["MINB"])
try: want = os.stat(ws)
except OSError: sys.exit(0)
best = None
for f in glob.glob(os.path.join(pd, "*.jsonl")):
    try:
        st = os.stat(f)
        if st.st_size < minb: continue
        cwd = None
        with open(f, encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i > 200: break
                try: d = json.loads(line)
                except Exception: continue
                if isinstance(d, dict) and d.get("cwd"): cwd = d["cwd"]; break
        if not cwd: continue
        c = os.stat(cwd)
        if (c.st_dev, c.st_ino) != (want.st_dev, want.st_ino): continue
    except OSError: continue
    if best is None or st.st_mtime > best[0]: best = (st.st_mtime, f)
if best: print(os.path.basename(best[1])[:-6])
' 2>/dev/null)"
    if [ -n "$f" ]; then echo "resume $f"; return; fi
    echo "new"
}

# 그 워크스페이스의 claude 가 살아 있나
#   ① 상태/<폴더>.pid 의 PID 가 claude 인가
#   ② 아니면 cwd 가 그 폴더인 claude 프로세스가 있나 (다른 경로로 띄운 것도 잡는다)
#   시각이 아니라 프로세스를 본다. 시각만 보다가 창을 두 번 띄운 적이 있다.
claude_alive() {
    local ws="$1" name pid p want cwd
    name="$(ws_name "$ws")"
    pid="$(cat "$STATE/$name.pid" 2>/dev/null)"
    if [ -n "${pid:-}" ] && [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "claude" ]; then
        CLAUDE_PID="$pid"; return 0
    fi
    # ★ 경로 문자열을 비교하지 않는다 — lsof 가 주는 경로는 NFD 라 글자가 다르다. inode 를 견준다.
    # ★ pgrep -x claude 는 편집기 터미널에서 띄운 claude 를 놓친 적이 있다. ps 의 comm 으로 고른다.
    want="$(stat -f %d:%i "$ws" 2>/dev/null)"
    for p in $(ps -axo pid=,comm= 2>/dev/null | awk '$2 ~ /(^|\/)claude$/ {print $1}'); do
        cwd="$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
        [ -n "$cwd" ] || continue
        if [ "$(stat -f %d:%i "$cwd" 2>/dev/null)" = "$want" ]; then
            echo "$p" > "$STATE/$name.pid"; CLAUDE_PID="$p"; return 0
        fi
    done
    rm -f "$STATE/$name.pid"; return 1
}

online() { curl -s -m 5 -o /dev/null https://www.google.com/generate_204 || ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; }
wait_online() {
    local t=0; while [ "$t" -lt "${1:-300}" ]; do online && return 0; sleep 10; t=$((t+10)); done; return 1
}

# 이 워크스페이스에서 함께 깨울 서비스 (선택) — 상태/서비스.txt 에 "폴더명 라벨1 라벨2"
services_for() {
    awk -v n="$1" '$1==n{for(i=2;i<=NF;i++) printf "%s ", $i}' "$STATE/서비스.txt" 2>/dev/null
}
