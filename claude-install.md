# 클로드코드용 설치 지시문 (claude 가 읽고 직접 수행한다)

> 사람이 읽는 문서가 아니다. 사용자가 클로드코드(VS Code 안 claude)에 이 파일의 주소를 주면서
> "이 지시대로 설치해줘" 라고 하면, claude 인 네가 아래 순서대로 **직접** 설치를 수행한다.
> 별도의 설치 파일을 더블클릭하게 하지 않는다.

## 무엇이 설치되나

- 워크스페이스 루트(사용자의 클로드코드 폴더) 아래 `재시작설정/` — 자동 재개 규칙의 단일 원본
- 루트 **바로 아래 폴더 하나하나**에 발판(`.vscode/tasks.json`)과 CLAUDE.md 관리 블록
  → 폴더를 VS Code 로 열면 claude 가 직전 대화를 자동으로 이어받고, 새 폴더도 다음 재개 때 자동 적용
- 자동 실행: 맥 launchd(`kr.claudecode.resume`·`.netwatch`) / 윈도우 작업 스케줄러(`ClaudeCode-자동재개`·`회선감시`)
  → PC 시작·회선 복구 때 모든 폴더의 claude 가 각각 되살아난다

## 설치 순서

### 1) 루트 확인 (반드시 사용자에게 먼저)

**기본값 = 지금 claude 가 실행 중인 폴더(cwd).** 단, cwd 가 `재시작설정` 또는 어느 워크스페이스의 하위로
보이면 그 상위(클로드코드 폴더)를 제안하라. 사용자에게 한 줄로 확인받는다:
"여기(`<경로>`)를 워크스페이스 루트로 잡고 설치할까요?" — 다운로드 폴더 같은 곳이면 반드시 짚어라.

### 2) 저장소 내려받기

임시 폴더에 받는다 (git 이 있으면 clone, 없으면 tar):

- 맥/리눅스: `curl -fsSL https://github.com/dmjo-creator/claude-auto-resume/archive/refs/heads/main.tar.gz | tar xz -C <임시폴더>`
- 윈도우: `Invoke-WebRequest https://github.com/dmjo-creator/claude-auto-resume/archive/refs/heads/main.tar.gz -OutFile <임시>\repo.tgz` 후 `tar -xzf`

받은 폴더 이름은 `claude-auto-resume-main` 이다.

### 3) 설치 실행

- **맥**: `bash <받은곳>/claude-auto-resume-main/kit/install/mac/설치.sh "<루트>"`
- **윈도우**: `powershell -NoProfile -ExecutionPolicy Bypass -File <받은곳>\claude-auto-resume-main\kit\install\win\install.ps1 -Root "<루트>"`

주의: 설치 대상에 이미 **원본(개발용)** 재시작설정이 있으면(`설정.sh` 존재) 설치기가 거부한다. 그대로 멈추고 사용자에게 알려라.

### 4) 스크립트 실행이 보안으로 막히면 — 같은 일을 네가 단계별로 직접

install.ps1(또는 설치.sh)을 **읽고**, 같은 단계를 네 도구로 수행하라:
1. `kit/payload/` → `<루트>/재시작설정/` 복사 (기존 `설정.txt`·`상태/`·`프롬프트/` 의 사용자 파일은 덮지 말 것)
2. `설정.txt` 의 `루트=__ROOT__` 를 실제 경로로 치환 (경로는 NFC 정규화)
3. VS Code 사용자 settings.json 에 `"task.allowAutomaticTasks": "on"` (JSON 을 깨뜨리지 말 것)
4. sync 실행(`sync.sh` / `win\sync.ps1`) — 이것도 막히면 그 내용대로 각 폴더에 발판·CLAUDE.md 블록을 직접 써라
5. 자동 실행 등록 — 윈도우: `schtasks /Create /TN ClaudeCode-자동재개 /TR "powershell -NoProfile -ExecutionPolicy Bypass -File <루트>\재시작설정\win\resume-all.ps1" /SC ONLOGON /F` (회선감시도 같은 형식, `netwatch.ps1`) · 맥: 설치.sh 안의 plist 생성 로직대로 launchd 2개
   - schtasks 마저 막히면 시작프로그램 폴더(`shell:startup`) 차선책을 쓰고 그렇게 했다고 보고하라

### 5) 검증하고 보고 (반드시)

- 맥 `launchctl list | grep kr.claudecode` / 윈도우 `schtasks /Query /TN ClaudeCode-자동재개` 확인
- sync 를 한 번 더 돌려 `[!]` 경고가 없는지, 각 폴더에 발판·블록이 생겼는지 확인
- 사용자에게 보고: 등록된 것 · 적용된 폴더 목록 · 끄는 법(`<루트>/재시작설정/상태/.전체끔` 파일 생성)

## 하지 말 것

- 루트 확인(1번) 없이 진행하지 마라. 워크스페이스 폴더들 안에 재시작설정 외의 재개 장치를 만들지 마라.
- 기존 `설정.txt`·`상태/`·대화 이력·사용자 프롬프트를 덮어쓰지 마라.

## 제거를 요청받으면

`kit/install/mac/제거.sh` 또는 `kit\install\win\uninstall.ps1` (또는 launchd bootout / `schtasks /Delete` 2개).
각 폴더의 발판·CLAUDE.md 블록과 `재시작설정/` 삭제는 사용자에게 물어보고 하라.
