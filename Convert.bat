@echo off
setlocal
cd /d "%~dp0"
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0AVI-to-MP4.ps1"
exit /b
