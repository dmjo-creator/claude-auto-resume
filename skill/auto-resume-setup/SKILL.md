---
name: auto-resume-setup
description: 클로드코드 자동 재시작·재개 장치를 이 PC 에 설치한다 (맥 launchd / 윈도우 작업 스케줄러). "자동재개 설치", "재시작 설정 설치", "이 폴더에 자동 재개 걸어줘" 요청 때 사용. 설치 파일 실행이 막힌 PC 에서도 동작한다.
---

# 자동재개 설치 스킬

이 스킬 폴더의 `꾸러미/` 안에 알맹이(payload)와 OS 별 설치 스크립트가 들어 있다.
너(claude)가 아래 순서대로 **직접** 설치를 수행한다. 별도의 설치 파일을 더블클릭하지 않는다.

## 무엇이 설치되나

- 워크스페이스 루트(사용자의 클로드코드 폴더) 아래에 `재시작설정/` 폴더가 생긴다 — 규칙의 단일 원본.
- 루트 **바로 아래 폴더 하나하나**에 발판(`.vscode/tasks.json`)과 CLAUDE.md 관리 블록이 심긴다.
  → 그 폴더를 VS Code 로 열면 claude 가 직전 대화를 자동으로 이어받는다. 새 폴더도 다음 재개 때 자동 적용.
- 자동 실행 등록: 맥은 launchd(`kr.claudecode.resume`·`.netwatch`), 윈도우는 작업 스케줄러
  (`ClaudeCode-자동재개`·`ClaudeCode-회선감시`). PC 시작·회선 복구 때 전체 재개가 돈다.

## 설치 순서

### 0) 스킬 폴더 위치 찾기

이 SKILL.md 가 있는 폴더가 스킬 폴더다. 보통 다음 중 하나:
- 개인: `~/.claude/skills/auto-resume-setup/` (윈도우 `C:\Users\<이름>\.claude\skills\auto-resume-setup\`)
- 프로젝트: `<프로젝트>/.claude/skills/auto-resume-setup/`

그 안의 `꾸러미/` 를 쓴다. 없으면 사용자에게 스킬 폴더가 온전히 복사됐는지 물어라.

### 1) 워크스페이스 루트 정하기

**기본값 = 지금 claude 가 실행 중인 폴더(cwd).** 단, cwd 가 `재시작설정` 이나 워크스페이스 하위 폴더로 보이면 그 상위를 제안하라.
사용자에게 한 줄로 확인받는다: "여기(`<경로>`)를 워크스페이스 루트로 잡고 설치할까요?" — 다운로드 폴더 같은 곳이면 반드시 짚어라.

### 2) 설치 실행 — 우선 OS 설치 스크립트를 그대로 돌린다

- **맥**: `bash "<스킬폴더>/꾸러미/install/mac/설치.sh" "<루트>"`
- **윈도우**: `powershell -NoProfile -ExecutionPolicy Bypass -File "<스킬폴더>\꾸러미\install\win\install.ps1" -Root "<루트>"`

스크립트가 하는 일: payload 복사(기존 설치가 있으면 `설정.txt`·`상태/` 보존) → `설정.txt` 의 `루트=` 채움 →
VS Code `task.allowAutomaticTasks: "on"` → sync(발판·규칙 심기) → 자동 실행 등록 → 루트에 재시작 바로가기.

### 3) 스크립트 실행이 막히면 — 같은 일을 네가 단계별로 직접 한다 (윈도우 기준)

보안 정책으로 `.ps1` 파일 실행이 막힌 PC 가 있다. 그때는 install.ps1 을 열어 **읽고**, 같은 단계를 네 도구로 수행하라:

1. `꾸러미/payload/` → `<루트>\재시작설정\` 복사 (기존 `설정.txt`·`상태\` 는 덮어쓰지 말 것)
2. `<루트>\재시작설정\설정.txt` 의 `루트=__ROOT__` 를 실제 루트 경로로 치환 (경로는 NFC 정규화)
3. VS Code `%APPDATA%\Code\User\settings.json` 에 `"task.allowAutomaticTasks": "on"` 추가 (JSON 을 깨뜨리지 말 것)
4. sync 수행: `powershell -File ...\재시작설정\win\sync.ps1` — 이것도 막히면 sync.ps1 의 내용대로
   각 워크스페이스에 `.vscode\tasks.json` 발판과 CLAUDE.md 관리 블록을 직접 써라 (내용은 sync.ps1 안에 있다)
5. 작업 스케줄러 등록 (`schtasks` 는 명령이라 파일 실행 제한과 무관하게 대개 된다):
   - `ClaudeCode-자동재개`: 로그온 시 1회 → `powershell -NoProfile -ExecutionPolicy Bypass -File <루트>\재시작설정\win\resume-all.ps1`
   - `ClaudeCode-회선감시`: 로그온 시 시작·상시 → `...\win\netwatch.ps1`
   - `schtasks /Create /TN <이름> /TR "<명령>" /SC ONLOGON /F` 형태. 관리자 권한 불필요.
   - schtasks 마저 막히면: 시작프로그램 폴더(`shell:startup`)에 `재시작.cmd` 바로가기를 넣는 차선책을 쓰고, 회선감시는 포기했다고 보고하라.

맥에서 같은 상황이면 install/mac/설치.sh 를 읽고 동일하게 단계별로 수행하라 (launchd plist 는 스크립트 안에 생성 로직이 있다).

### 4) 검증 (반드시)

- 맥: `launchctl list | grep kr.claudecode` 에 resume·netwatch 둘 다 있는가
- 윈도우: `schtasks /Query /TN ClaudeCode-자동재개` · `/TN ClaudeCode-회선감시` 가 나오는가
- sync 를 한 번 더 돌려 `[!]` 경고가 없는가, 루트 아래 각 폴더에 발판·CLAUDE.md 블록이 생겼는가
- 결과를 사용자에게 보고: 등록된 것 / 심긴 폴더 목록 / 끄는 법(`재시작설정/상태/.전체끔` 파일 생성)

## 하지 말 것

- 워크스페이스 폴더들 안에 재시작설정 외의 재개 스크립트·표식·로그를 만들지 마라 (규칙은 `재시작설정/` 하나뿐).
- 사용자의 기존 `설정.txt`·`상태/`·대화 이력을 덮어쓰지 마라.
- 설치 대상 확인(1번) 없이 진행하지 마라.

## 제거를 요청받으면

- 맥: `bash 꾸러미/install/mac/제거.sh` (또는 launchd 2개 bootout + plist 삭제)
- 윈도우: `powershell -File 꾸러미\install\win\uninstall.ps1` (또는 `schtasks /Delete /TN <이름> /F` 2개)
- 각 폴더의 발판·CLAUDE.md 블록과 `재시작설정/` 폴더는 물어보고 지워라.
