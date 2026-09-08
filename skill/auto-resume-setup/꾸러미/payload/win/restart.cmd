@echo off
title Claude Code restart all
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart.ps1"
echo.
pause
