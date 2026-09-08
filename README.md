# 클로드코드 자동재개 설치 저장소

PC 를 켜거나 인터넷이 복구될 때, 워크스페이스 폴더들을 VS Code 로 열고 각 폴더의
claude 가 직전 대화를 자동으로 이어받게 하는 장치다. 규칙은 `재시작설정/` 폴더 하나에만 두고,
루트 바로 아래 새 폴더는 자동으로 적용된다.

## 설치 — 한 줄

**클로드코드 폴더(워크스페이스 루트)에서** 실행한다. 실행한 폴더가 설치 대상이 된다.

맥 (터미널):
```bash
curl -fsSL https://raw.githubusercontent.com/__OWNER__/claude-auto-resume/main/install.sh | bash
```

윈도우 (PowerShell):
```powershell
irm https://raw.githubusercontent.com/__OWNER__/claude-auto-resume/main/install.ps1 | iex
```

명령 실행이 막힌 PC 는 **클로드코드에게 시키면 된다** — 클로드코드를 루트 폴더에서 열고:
```
https://github.com/__OWNER__/claude-auto-resume 저장소의 skill/auto-resume-setup 을
~/.claude/skills 에 설치하고 /auto-resume-setup 을 수행해줘
```

## 구조

| 경로 | 내용 |
|---|---|
| `install.sh` / `install.ps1` | 한 줄 설치 부트스트랩 (저장소를 받아 kit 설치기를 돌린다) |
| `kit/` | 알맹이 — payload(공용 규칙·스크립트) + install/mac·win |
| `skill/auto-resume-setup/` | 클로드코드 스킬판 — claude 가 지시문을 읽고 직접 설치 |

끄기: `<루트>/재시작설정/상태/.전체끔` 파일 생성 · 제거: `kit/install/mac/제거.sh` 또는 `kit\install\win\uninstall.ps1`
