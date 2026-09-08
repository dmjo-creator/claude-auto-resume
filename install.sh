#!/bin/bash
# 클로드코드 자동재개 — 맥 한 줄 설치
#   curl -fsSL https://raw.githubusercontent.com/dmjo-creator/claude-auto-resume/main/install.sh | bash
#   (설치 대상 = 명령을 실행한 현재 폴더. 다른 폴더는:  ... | bash -s -- /경로)
set -eu
ROOT="${1:-$PWD}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "저장소를 내려받는다..."
curl -fsSL "https://github.com/dmjo-creator/claude-auto-resume/archive/refs/heads/main.tar.gz" | tar xz -C "$TMP"
bash "$TMP"/claude-auto-resume-*/kit/install/mac/설치.sh "$ROOT"
