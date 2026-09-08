#!/bin/bash
# -----------------------------------------------------------------------------
# 클로드코드 자동재개 — 설치 (맥)
#
#     bash install/mac/설치.sh [워크스페이스루트] [--no-register] [--quiet]
#
# 하는 일
#   1) 워크스페이스 루트를 정한다 (기본 ~/클로드코드, 없으면 만든다)
#   2) 루트 아래 '재시작설정' 폴더로 payload 를 복사한다 (덮어쓸 땐 설정·상태를 지킨다)
#   3) 설정.txt 의 루트를 이 PC 경로로 채운다
#   4) VS Code 의 자동 작업 허용을 켠다 (task.allowAutomaticTasks = on)
#   5) 모든 워크스페이스에 발판·규칙을 심는다 (sync.sh)
#   6) launchd 2개를 등록한다 — 로그인 때 재개 · 회선 감시
#   7) 루트에 '재시작.command' 바로가기를 둔다
# -----------------------------------------------------------------------------
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/../.." && pwd)"
PAYLOAD="$PKG/payload"
LABEL_RESUME="kr.claudecode.resume"
LABEL_NETWATCH="kr.claudecode.netwatch"
REGISTER=1; QUIET=0; ROOT_ARG=""
for a in "$@"; do
    case "$a" in
        --no-register) REGISTER=0 ;;
        --quiet) QUIET=1 ;;
        -*) ;;
        *) ROOT_ARG="$a" ;;
    esac
done
say() { [ "$QUIET" = 1 ] || echo "$@"; }

echo "==============================================================="
echo "  클로드코드 자동재개 설치 (맥)"
echo "==============================================================="
echo

# ── 0) 준비물 점검 ───────────────────────────────────────────────────────────
MISSING=0
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 이 없다. 맥 기본 python3 이 필요하다 (Xcode 명령줄 도구)."; MISSING=1; }
[ -d "/Applications/Visual Studio Code.app" ] || echo "[·] VS Code 가 안 보인다 — 나중에 설치해도 된다 (그때까진 터미널로 뜬다)."
command -v claude >/dev/null 2>&1 || echo "[·] claude 명령을 못 찾았다 — 나중에 설치해도 된다 (설치 자체는 끝까지 진행한다)."
[ "$MISSING" = 0 ] || { echo; echo "필수 준비물이 없어 멈춘다."; exit 1; }

# ── 1) 워크스페이스 루트 ─────────────────────────────────────────────────────
DEFAULT_ROOT="$HOME/클로드코드"
if [ -n "$ROOT_ARG" ]; then ROOT="$ROOT_ARG"
elif [ -t 0 ]; then
    echo "워크스페이스들이 들어 있는(또는 앞으로 들어갈) 폴더를 정한다."
    printf '  그냥 엔터를 누르면: %s\n  > ' "$DEFAULT_ROOT"
    read -r ROOT
    [ -n "$ROOT" ] || ROOT="$DEFAULT_ROOT"
else ROOT="$DEFAULT_ROOT"; fi
ROOT="${ROOT/#\~/$HOME}"
ROOT="$(python3 -c 'import sys,unicodedata,os; sys.stdout.write(unicodedata.normalize("NFC", os.path.abspath(os.path.expanduser(sys.argv[1]))))' "$ROOT")"
mkdir -p "$ROOT" || { echo "[!] 폴더를 만들지 못했다: $ROOT"; exit 1; }
CFG="$ROOT/재시작설정"
echo
say "  루트      : $ROOT"
say "  설치 위치 : $CFG"
echo

# ── 2) 복사 ─────────────────────────────────────────────────────────────────
mkdir -p "$CFG"
KEEP_CFG=0
if [ -f "$CFG/설정.txt" ]; then KEEP_CFG=1; cp "$CFG/설정.txt" "$CFG/.설정.txt.이전"; fi
for item in lib.sh sync.sh resume_all.sh resume_claude.sh netwatch.sh 재시작.command README.md win; do
    [ -e "$PAYLOAD/$item" ] || continue
    rm -rf "$CFG/$item"
    cp -R "$PAYLOAD/$item" "$CFG/$item"
done
mkdir -p "$CFG/상태" "$CFG/프롬프트"
# 프롬프트·상태의 사용자 파일은 덮어쓰지 않는다
for f in "$PAYLOAD/프롬프트/"*; do b="$(basename "$f")"; [ -f "$CFG/프롬프트/$b" ] || cp "$f" "$CFG/프롬프트/$b"; done
for f in "$PAYLOAD/상태/"*; do b="$(basename "$f")"; [ -f "$CFG/상태/$b" ] || cp "$f" "$CFG/상태/$b"; done
chmod +x "$CFG"/*.sh "$CFG/재시작.command" 2>/dev/null
say "  파일 복사 완료"

# ── 3) 설정.txt ─────────────────────────────────────────────────────────────
if [ "$KEEP_CFG" = 1 ]; then
    mv "$CFG/.설정.txt.이전" "$CFG/설정.txt"
    say "  설정.txt : 이미 있던 것을 그대로 둔다 (루트만 확인한다)"
    python3 - "$CFG/설정.txt" "$ROOT" <<'PY'
import sys, pathlib, re
p, root = pathlib.Path(sys.argv[1]), sys.argv[2]
s = p.read_text(encoding="utf-8")
new, n = re.subn(r'(?m)^루트=.*$', '루트=' + root, s)
if n == 0: new = s.rstrip("\n") + "\n루트=" + root + "\n"
if new != s: p.write_text(new, encoding="utf-8"); print("  설정.txt : 루트를 이 PC 경로로 고쳤다")
PY
else
    python3 - "$PAYLOAD/설정.txt" "$CFG/설정.txt" "$ROOT" <<'PY'
import sys, pathlib
src, dst, root = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
dst.write_text(pathlib.Path(src).read_text(encoding="utf-8").replace("__ROOT__", root), encoding="utf-8")
PY
    say "  설정.txt : 새로 만들었다"
fi

# ── 4) VS Code 자동 작업 허용 ────────────────────────────────────────────────
S="$HOME/Library/Application Support/Code/User/settings.json"
mkdir -p "$(dirname "$S")"
python3 - "$S" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
key = '"task.allowAutomaticTasks"'
if not p.exists() or not p.read_text(encoding="utf-8").strip():
    p.write_text('{\n  "task.allowAutomaticTasks": "on"\n}\n', encoding="utf-8"); print("  편집기 설정 : 새로 만들고 자동 작업을 켰다"); raise SystemExit
s = p.read_text(encoding="utf-8")
if re.search(r'"task\.allowAutomaticTasks"\s*:\s*"on"', s): print("  편집기 설정 : 자동 작업 이미 켜져 있다"); raise SystemExit
if key in s:
    s2 = re.sub(r'"task\.allowAutomaticTasks"\s*:\s*"[^"]*"', '"task.allowAutomaticTasks": "on"', s)
else:
    i = s.find("{")
    if i < 0: print("  [!] 편집기 설정 파일을 이해하지 못했다 — 손으로 켤 것"); raise SystemExit
    s2 = s[:i+1] + '\n  "task.allowAutomaticTasks": "on",' + s[i+1:]
p.with_suffix(".json.자동재개설치전").write_text(s, encoding="utf-8")
p.write_text(s2, encoding="utf-8")
print("  편집기 설정 : 자동 작업을 켰다 (원본은 settings.json.자동재개설치전 로 남겼다)")
PY

# ── 5) 발판·규칙 심기 ────────────────────────────────────────────────────────
echo
bash "$CFG/sync.sh"

# ── 6) launchd 등록 ─────────────────────────────────────────────────────────
echo
if [ "$REGISTER" = 1 ]; then
    # (시험용 갈고리: AUTORESUME_LA_DIR 을 주면 그 폴더에 plist 만 쓰고 등록은 하지 않는다)
    LA="${AUTORESUME_LA_DIR:-$HOME/Library/LaunchAgents}"; mkdir -p "$LA"; UID_N="$(id -u)"
    NO_BOOTSTRAP=0; [ -n "${AUTORESUME_LA_DIR:-}" ] && NO_BOOTSTRAP=1
    write_plist() {   # 라벨 스크립트 추가키
        cat > "$LA/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$CFG/$2</string>
$4  </array>
  <key>WorkingDirectory</key><string>$CFG</string>
  <key>RunAtLoad</key><true/>
$3
  <key>StandardOutPath</key><string>$CFG/상태/_launchd_$1.log</string>
  <key>StandardErrorPath</key><string>$CFG/상태/_launchd_$1.err</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>LANG</key><string>ko_KR.UTF-8</string>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
PLIST
        plutil -lint "$LA/$1.plist" >/dev/null || { echo "  [!] plist 문법 오류: $1"; return 1; }
        [ "$NO_BOOTSTRAP" = 1 ] && { echo "  plist 만 만들었다(시험): $1"; return 0; }
        launchctl bootout "gui/$UID_N/$1" >/dev/null 2>&1
        if launchctl bootstrap "gui/$UID_N" "$LA/$1.plist" 2>/dev/null; then echo "  자동실행 등록: $1"
        else echo "  [!] 자동실행 등록 실패: $1 (다시 로그인한 뒤 이 설치를 한 번 더 돌려볼 것)"; fi
    }
    # 로그인 때 한 번 — 창을 열고 나면 launchd 손을 떠나야 하므로 AbandonProcessGroup
    write_plist "$LABEL_RESUME" "resume_all.sh" "  <key>AbandonProcessGroup</key><true/>" \
"    <string>--why</string>
    <string>맥 시작</string>
"
    # 상시 — 죽으면 되살린다
    write_plist "$LABEL_NETWATCH" "netwatch.sh" "  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>" ""
else
    say "  (--no-register: 자동실행 등록은 건너뛴다)"
fi

# ── 7) 루트 바로가기 ────────────────────────────────────────────────────────
cat > "$ROOT/재시작.command" <<SH
#!/bin/bash
# 더블클릭 → 모든 워크스페이스 재시작. 규칙은 재시작설정/ 에 있다.
exec bash "$CFG/재시작.command"
SH
chmod +x "$ROOT/재시작.command"

echo
echo "==============================================================="
echo "  설치 끝"
echo "==============================================================="
echo "  설정 고치기   : $CFG/설정.txt"
echo "  설명서        : $CFG/README.md"
echo "  손으로 재시작 : $ROOT/재시작.command  (더블클릭)"
echo "  전부 끄기     : touch \"$CFG/상태/.전체끔\""
echo
echo "  이제 PC 를 켤 때마다, 그리고 인터넷이 끊겼다 돌아올 때마다"
echo "  워크스페이스 폴더들이 편집기에서 자동으로 열리고 claude 가 이어받는다."
echo
if [ -t 0 ] && [ "$QUIET" = 0 ]; then printf '  엔터를 누르면 닫는다. '; read -r _; fi
