# 클로드코드 자동재개 설치 저장소

PC 를 켜거나 인터넷이 복구될 때, 워크스페이스 폴더들을 VS Code 로 열고 각 폴더의
claude 가 직전 대화를 자동으로 이어받게 하는 장치다. 규칙은 `재시작설정/` 폴더 하나에만 두고,
루트 바로 아래 새 폴더는 자동으로 적용된다.

## 설치 — 한 줄

**클로드코드 폴더(워크스페이스 루트)에서** 실행한다. 실행한 폴더가 설치 대상이 된다.

맥 (터미널):
```bash
curl -fsSL https://raw.githubusercontent.com/dmjo-creator/claude-auto-resume/main/install.sh | bash
```

윈도우 (PowerShell):
```powershell
irm https://raw.githubusercontent.com/dmjo-creator/claude-auto-resume/main/install.ps1 | iex
```

**VS Code 안 클로드코드 실행 중이라면** — 터미널을 열 것 없이, 클로드코드 대화창에 아래 한 줄을 붙여넣는다
(클로드코드를 **클로드코드 폴더(루트)에서** 열었을 때. claude 가 지시문을 읽고 내려받기 → 설치 → 자동실행 등록 → 검증까지 직접 한다):
```
https://raw.githubusercontent.com/dmjo-creator/claude-auto-resume/main/claude-install.md 의 지시대로 이 폴더에 자동재개를 설치해줘
```
셸 명령 실행까지 막힌 PC 에서도 이 방법은 된다 — claude 가 파일 도구로 단계를 대신 수행한다 (지시문에 우회 절차 포함).

스킬로 등록해 두고 쓰려면:
```
https://github.com/dmjo-creator/claude-auto-resume 저장소의 skill/auto-resume-setup 을
~/.claude/skills 에 설치하고 /auto-resume-setup 을 수행해줘
```

## 구조

| 경로 | 내용 |
|---|---|
| `install.sh` / `install.ps1` | 한 줄 설치 부트스트랩 (저장소를 받아 kit 설치기를 돌린다) |
| `claude-install.md` | 클로드코드용 설치 지시문 — claude 가 읽고 직접 설치한다 |
| `kit/` | 알맹이 — payload(공용 규칙·스크립트) + install/mac·win |
| `skill/auto-resume-setup/` | 클로드코드 스킬판 — claude 가 지시문을 읽고 직접 설치 |

## 권한과 안전

되살아난 claude 는 **권한을 묻지 않고** 뜬다 (`--dangerously-skip-permissions`). 자동재개는 사람이
안 보는 사이에 뜨는 것이라, 권한을 물으면 아무도 답하지 못해 claude 가 도구를 하나도 못 쓴 채
그 자리에서 멈춰 버리기 때문이다. 대신 각 폴더에 주는 첫 지시(`재시작설정/프롬프트/`)가
**읽고 점검해서 보고**로 끝나, 사람이 없는 사이에 파일을 고치거나 발행·전송하지 않게 한다.

묻게 하고 싶으면 설치 후 그 플래그를 지운다 — 맥은 `재시작설정/resume_claude.sh` 의 `exec claude …` 줄,
윈도우는 `재시작설정/win/resume-claude.ps1` 의 `& $claude …` 줄.

끄기: `<루트>/재시작설정/상태/.전체끔` 파일 생성 · 제거: `kit/install/mac/제거.sh` 또는 `kit\install\win\uninstall.ps1`
